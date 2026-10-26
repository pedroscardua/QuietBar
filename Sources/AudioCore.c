#include "AudioCore.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <math.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <pthread.h>
#include <time.h>
#include <string.h>

#define CAPACITY 32768
#define CHUNK 4096
typedef struct {
    int fd; uint64_t frames, period, diskPosition;
    float ring[CAPACITY*2];
    _Atomic uint64_t readCount, writeCount;
} Stem;
struct QBEngine {
    Stem stems[10][2];
    uint64_t elapsed;
    _Atomic double target[10], volume, width;
    _Atomic int dynamics;
    double gain[10], master, stereo, reduction;
    pthread_t worker; int workerStarted;
    _Atomic int running;
    _Atomic uint64_t underruns;
};
static void fill(Stem *s) {
    if(s->fd<0 || !s->period)return;
    uint64_t w=atomic_load_explicit(&s->writeCount,memory_order_relaxed);
    uint64_t r=atomic_load_explicit(&s->readCount,memory_order_acquire);
    while(w-r<=CAPACITY-CHUNK) {
        float *out=s->ring+(w%CAPACITY)*2;
        uint64_t todo=CHUNK;
        while(todo) {
            uint64_t end=s->frames<s->period?s->frames:s->period;
            uint64_t n;
            if(s->diskPosition<end) {
                n=end-s->diskPosition;if(n>todo)n=todo;
                ssize_t got=pread(s->fd,out,n*8,s->diskPosition*8);
                if(got<(ssize_t)n*8)memset((char*)out+(got>0?got:0),0,n*8-(got>0?got:0));
            } else {
                n=s->period-s->diskPosition;if(n>todo)n=todo;
                memset(out,0,n*8);
            }
            todo-=n;out+=n*2;s->diskPosition=(s->diskPosition+n)%s->period;
        }
        w+=CHUNK;atomic_store_explicit(&s->writeCount,w,memory_order_release);
        r=atomic_load_explicit(&s->readCount,memory_order_acquire);
    }
}
static void *loader(void *arg) {
    QBEngine *e=arg;struct timespec wait={0,100000000};
    while(atomic_load(&e->running)) {
        for(int i=0;i<10;i++)for(int s=0;s<2;s++)fill(&e->stems[i][s]);
        nanosleep(&wait,NULL);
    }return NULL;
}
static double bound(double x, double lo, double hi) { return isfinite(x) ? fmax(lo, fmin(hi, x)) : lo; }
QBEngine *qb_create(void) {
    QBEngine *e = calloc(1, sizeof(*e));
    if (e) { atomic_init(&e->volume, 0.5); atomic_init(&e->width, 1); atomic_init(&e->dynamics, 1);
        for (int i=0;i<10;i++) atomic_init(&e->target[i], 0);
        e->stereo=1;
        atomic_init(&e->running,0);atomic_init(&e->underruns,0);
        for(int i=0;i<10;i++)for(int s=0;s<2;s++) {
            e->stems[i][s].fd=-1;
            atomic_init(&e->stems[i][s].readCount,0);atomic_init(&e->stems[i][s].writeCount,0);
        }
    }
    return e;
}
void qb_destroy(QBEngine *e) {
    if (!e) return;
    atomic_store(&e->running,0);if(e->workerStarted)pthread_join(e->worker,NULL);
    for(int i=0;i<10;i++) for(int s=0;s<2;s++) if(e->stems[i][s].fd>=0)close(e->stems[i][s].fd);
    free(e);
}
int qb_load(QBEngine *e, int band, int side, const char *path) {
    if(!e || e->workerStarted || band<0 || band>=10 || side<0 || side>1) return 0;
    int fd=open(path,O_RDONLY); if(fd<0) return 0;
    struct stat st;
    if(fstat(fd,&st) || st.st_size<=0 || st.st_size%8) {close(fd);return 0;}
    Stem *a=&e->stems[band][side];
    if(a->fd>=0)close(a->fd);
    a->fd=fd;a->frames=(uint64_t)st.st_size/8;return 1;
}
int qb_prepare(QBEngine *e) {
    if(!e || e->workerStarted)return 0;
    for(int i=0;i<10;i++) {
        double a=round((double)e->stems[i][0].frames/44100*8)/8;
        double b=round((double)e->stems[i][1].frames/44100*8)/8;
        uint64_t period=llround((a+b)*0.5*44100);
        for(int s=0;s<2;s++) {if(e->stems[i][s].fd<0||!period)return 0;e->stems[i][s].period=period;fill(&e->stems[i][s]);}
    }
    atomic_store(&e->running,1);
    if(pthread_create(&e->worker,NULL,loader,e))return 0;
    e->workerStarted=1;return 1;
}
uint64_t qb_underruns(QBEngine *e){return atomic_load(&e->underruns);}
void qb_level(QBEngine *e,int i,double x) {if(i>=0&&i<10) {x=round(bound(x,0,0.99)*1000)/1000;atomic_store_explicit(&e->target[i],x*x*x,memory_order_relaxed);}}
void qb_master(QBEngine *e,double x){atomic_store_explicit(&e->volume,bound(x,0,1),memory_order_relaxed);}
void qb_width(QBEngine *e,double x){atomic_store_explicit(&e->width,bound(x,0,2),memory_order_relaxed);}
void qb_dynamics(QBEngine *e,int x){atomic_store_explicit(&e->dynamics,!!x,memory_order_relaxed);}
void qb_render(QBEngine *e,float *left,float *right,uint32_t count) {
    // 44.1 kHz stereo. No allocation, locks, I/O, or Objective-C on the audio thread.
    const double smooth=1-exp(-1.0/(44100*0.1));
    const double attack=exp(-1.0/(44100*0.05)),release=exp(-1.0/(44100*2));
    double targets[10];uint64_t delays[10];
    for(int i=0;i<10;i++) {
        targets[i]=atomic_load_explicit(&e->target[i],memory_order_relaxed);
        double a=round((double)e->stems[i][0].frames/44100*8)/8;
        delays[i]=(uint64_t)llround(a*0.5*44100);
    }
    double master=atomic_load_explicit(&e->volume,memory_order_relaxed);
    double width=atomic_load_explicit(&e->width,memory_order_relaxed);
    int dynamics=atomic_load_explicit(&e->dynamics,memory_order_relaxed);
    for(uint32_t n=0;n<count;n++) {
        double l=0,r=0;
        for(int i=0;i<10;i++) {
            e->gain[i]+=(targets[i]-e->gain[i])*smooth;
            for(int s=0;s<2;s++) {
                if(s && e->elapsed<delays[i]) continue;
                Stem *a=&e->stems[i][s];
                uint64_t pos=atomic_load_explicit(&a->readCount,memory_order_relaxed);
                if(pos<atomic_load_explicit(&a->writeCount,memory_order_acquire)) {
                    l+=a->ring[(pos%CAPACITY)*2]*e->gain[i];r+=a->ring[(pos%CAPACITY)*2+1]*e->gain[i];
                    atomic_store_explicit(&a->readCount,pos+1,memory_order_release);
                } else atomic_fetch_add_explicit(&e->underruns,1,memory_order_relaxed);
            }
        }
        e->elapsed++;
        e->master+=(master-e->master)*smooth;
        e->stereo+=(width-e->stereo)*smooth;
        l*=e->master;r*=e->master;
        double mid=(l+r)*0.5,side=(l-r)*0.5*e->stereo;
        l=mid+side;r=mid-side;
        if(dynamics) {
            // Linked stereo soft-knee compressor, matching the site's nominal settings.
            // Its detector differs from Web Audio's implementation; not bit-identical.
            double db=20*log10(fmax(fabs(l),fabs(r))+1e-12),x=db+12,gr=0;
            if(x>3)gr=-0.9*x;else if(x>-3)gr=-0.9*(x+3)*(x+3)/12;
            double coeff=gr<e->reduction?attack:release;
            e->reduction=coeff*e->reduction+(1-coeff)*gr;
            double gain=pow(10,e->reduction/20);l*=gain;r*=gain;
        } else e->reduction=0;
        // Final safety ceiling; normal preset levels stay below this.
        left[n]=(float)bound(l,-0.999,0.999);right[n]=(float)bound(r,-0.999,0.999);
    }
}
