"""Real-time streaming check, independent sample reference, and output controls."""
import ctypes, math, mmap, struct, time, json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
lib=ctypes.CDLL(str(ROOT/'build/libAudioCore.dylib'))
lib.qb_create.restype=ctypes.c_void_p
for name,args in {'qb_load':[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_char_p], 'qb_prepare':[ctypes.c_void_p], 'qb_level':[ctypes.c_void_p,ctypes.c_int,ctypes.c_double], 'qb_master':[ctypes.c_void_p,ctypes.c_double], 'qb_width':[ctypes.c_void_p,ctypes.c_double], 'qb_dynamics':[ctypes.c_void_p,ctypes.c_int], 'qb_render':[ctypes.c_void_p,ctypes.POINTER(ctypes.c_float),ctypes.POINTER(ctypes.c_float),ctypes.c_uint32], 'qb_destroy':[ctypes.c_void_p], 'qb_underruns':[ctypes.c_void_p]}.items():getattr(lib,name).argtypes=args
lib.qb_underruns.restype=ctypes.c_uint64
core=lib.qb_create(); assert core
A=['0b','1a','2a','3a','4b','5b','6b','7a','8b','9b']
B=['0a','1b','2b','3b','4a','5a','6a','7b','8a','9a']
levels=[.42,.55,.64,.75,.53,.58,.47,.35,.30,.26]
files=[];maps={}
for i in range(10):
 for side,names in enumerate([A,B]):
  p=ROOT/'build/audio'/(names[i]+'.f32'); assert lib.qb_load(core,i,side,str(p).encode())
  f=p.open('rb');files.append(f);maps[names[i]]=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ)
 lib.qb_level(core,i,levels[i])
assert lib.qb_prepare(core)
assert not lib.qb_prepare(core), "Repeated prepare must be rejected"
assert not lib.qb_load(core,0,0,str(ROOT/'build/audio/0a.f32').encode()), "Loading while rendering must be rejected"
lib.qb_dynamics(core,0)
left=(ctypes.c_float*512)();right=(ctypes.c_float*512)()
clock=0;peak=0;errors=[];cpu=0;start=time.monotonic(); sample_targets=[44100,44100*13,44100*26]
try:
 while clock<44100*29:
  t=time.perf_counter();lib.qb_render(core,left,right,512);cpu+=time.perf_counter()-t
  for n in [0,511]:
   assert math.isfinite(left[n]) and abs(left[n])<=1
   peak=max(peak,abs(left[n]),abs(right[n]))
  for target in sample_targets:
   if clock<=target<clock+512:
    ref=[0.,0.]
    for i in range(10):
     dur=24-i;period=dur*44100;delay=period//2
     for names,offset in [(A,0),(B,delay)]:
      if target<offset:continue
      pos=((target-offset)%period)*8
      l,r=struct.unpack_from('<ff',maps[names[i]],pos)
      gain=levels[i]**3*(1-math.exp(-(target+1)/(44100*.1)))
      ref[0]+=l*gain;ref[1]+=r*gain
    master=.5*(1-math.exp(-(target+1)/(44100*.1)))
    actual=[left[target-clock],right[target-clock]]
    error=max(abs(actual[c]-ref[c]*master) for c in range(2));errors.append(error)
    assert error<2e-6,(target,error)
  clock+=512
  if clock>=44100*27:lib.qb_width(core,0)
  if clock>=44100*28:assert max(abs(left[i]-right[i]) for i in range(512))<1e-4
  time.sleep(max(0,start+clock/44100-time.monotonic()))
 assert lib.qb_underruns(core)==0,lib.qb_underruns(core)
 result={'seconds':clock/44100,'peak':peak,'reference_max_error':max(errors),'underruns':lib.qb_underruns(core),'render_cpu_seconds':cpu,'render_realtime_percent':cpu/(clock/44100)*100}
 (ROOT/'build/reports/audio-test.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))
finally:
 lib.qb_destroy(core)
 for m in maps.values():m.close()
 for f in files:f.close()
