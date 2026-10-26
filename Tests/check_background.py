"""Silent real-time soak: repetitions, pause/resume, control stress and bounded RSS."""
import ctypes,json,math,time,threading,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
lib=ctypes.CDLL(str(ROOT/'build/libAudioCore.dylib'))
lib.qb_create.restype=ctypes.c_void_p
args={'qb_load':[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_char_p],'qb_prepare':[ctypes.c_void_p], 'qb_render':[ctypes.c_void_p,ctypes.POINTER(ctypes.c_float),ctypes.POINTER(ctypes.c_float),ctypes.c_uint32], 'qb_level':[ctypes.c_void_p,ctypes.c_int,ctypes.c_double], 'qb_master':[ctypes.c_void_p,ctypes.c_double], 'qb_width':[ctypes.c_void_p,ctypes.c_double], 'qb_dynamics':[ctypes.c_void_p,ctypes.c_int], 'qb_underruns':[ctypes.c_void_p], 'qb_destroy':[ctypes.c_void_p]}
for n,a in args.items():getattr(lib,n).argtypes=a
lib.qb_underruns.restype=ctypes.c_uint64
core=lib.qb_create();assert core
A=['0b','1a','2a','3a','4b','5b','6b','7a','8b','9b'];B=['0a','1b','2b','3b','4a','5a','6a','7b','8a','9a']
for i in range(10):
 for s,names in enumerate([A,B]):assert lib.qb_load(core,i,s,str(ROOT/'build/audio'/(names[i]+'.f32')).encode())
 lib.qb_level(core,i,.5)
assert lib.qb_prepare(core)
left=(ctypes.c_float*512)();right=(ctypes.c_float*512)()
stop=threading.Event()
def controls():
 n=0
 while not stop.wait(.04):
  for i in range(10):lib.qb_level(core,i,.99 if n%7==0 else .1+.8*(.5+.5*math.sin(n*.1+i)))
  lib.qb_width(core,[0.,.5,1.,2.][n%4]);lib.qb_dynamics(core,n%2)
  lib.qb_master(core,0. if n%11==0 else .8);n+=1
worker=threading.Thread(target=controls);worker.start()
start=time.monotonic();clock=0;rss=[];paused=False;peak=0
try:
 while clock<44100*75:
  if clock>=44100*35 and not paused:
   time.sleep(2);start+=2;paused=True
  lib.qb_render(core,left,right,512)
  for k in range(512):
   assert math.isfinite(left[k]) and math.isfinite(right[k])
   assert abs(left[k])<=1 and abs(right[k])<=1
   peak=max(peak,abs(left[k]),abs(right[k]))
  clock+=512
  if clock% (512*86)==0:
   import os
   rss.append(int(subprocess.check_output(['ps','-o','rss=','-p',str(os.getpid())])))
  time.sleep(max(0,start+clock/44100-time.monotonic()))
 stop.set();worker.join()
 # Allow controls to settle, then verify silence and mono independently.
 lib.qb_width(core,0);lib.qb_master(core,0)
 for block in range(150):
  lib.qb_render(core,left,right,512);time.sleep(512/44100)
 assert max(abs(v) for v in left)<1e-6
 assert max(abs(left[i]-right[i]) for i in range(512))<1e-7
 underruns=lib.qb_underruns(core);assert underruns==0,underruns
 stable=rss[10:]
 assert max(stable)-min(stable)<8192,(min(stable),max(stable))
 result={'render_seconds':clock/44100,'pause_resume_seconds':2,'peak':peak,'underruns':underruns,'rss_after_warmup_min_kib':min(stable),'rss_after_warmup_max_kib':max(stable),'concurrent_control_updates':True,'mute_and_mono_passed':True}
 (ROOT/'build/reports/background-audio-test.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))
finally:stop.set();worker.join();lib.qb_destroy(core)
