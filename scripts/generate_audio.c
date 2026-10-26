// SPDX-License-Identifier: MIT
// Original deterministic filtered noise. No recordings or external assets.
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#define RATE 44100
static uint32_t rng;
static double noise(void) {
    rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5;
    return (double)rng / 2147483648.0 - 1.0;
}
int main(int argc, char **argv) {
    if (argc != 2) { fprintf(stderr, "usage: generate_audio OUTPUT_DIRECTORY\n"); return 1; }
    const double centers[10] = {31.25,62.5,125,250,500,1000,2000,4000,8000,14000};
    for (int band=0; band<10; band++) for (int side=0; side<2; side++) {
        size_t frames=(24-band)*RATE;
        float *data=calloc(frames*2,sizeof(float));
        if (!data) return 1;
        rng=0x51424152u+(uint32_t)(band*2+side)*7919u;
        double w=2*3.141592653589793*centers[band]/RATE;
        double alpha=sin(w)/(2*1.2), a0=1+alpha;
        double b0=alpha/a0, b2=-b0, a1=-2*cos(w)/a0, a2=(1-alpha)/a0;
        double x1[2]={0},x2[2]={0},y1[2]={0},y2[2]={0},sum=0,peak=0;
        for (size_t n=0;n<frames+RATE;n++) for(int ch=0;ch<2;ch++) {
            double x=noise(), y=b0*x+b2*x2[ch]-a1*y1[ch]-a2*y2[ch];
            x2[ch]=x1[ch];x1[ch]=x;y2[ch]=y1[ch];y1[ch]=y;
            if(n>=RATE) {
                size_t i=n-RATE;
                // 20 ms raised-cosine edges; staggered pairs cover the loop seam.
                double edge=fmin(1.0,fmin((double)i,(double)(frames-1-i))/(RATE*.02));
                y*=.5-.5*cos(3.141592653589793*edge);
                data[i*2+ch]=(float)y;sum+=y*y;peak=fmax(peak,fabs(y));
            }
        }
        double gain=fmin(.18/sqrt(sum/(frames*2)),.9/peak);
        for(size_t n=0;n<frames*2;n++) data[n]*=(float)gain;
        char path[4096];
        if(snprintf(path,sizeof(path),"%s/%d%c.f32",argv[1],band,'a'+side)>=(int)sizeof(path)) return 1;
        FILE *f=fopen(path,"wb");
        if(!f) {perror(path);free(data);return 1;}
        int ok=fwrite(data,sizeof(float),frames*2,f)==frames*2;
        if(fclose(f)!=0) ok=0;
        free(data);if(!ok)return 1;
    }
    puts("Generated 20 original noise layers (44.1 kHz, stereo float32).");
    return 0;
}
