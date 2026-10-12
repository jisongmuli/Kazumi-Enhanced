"""Check that RIFE generates a moving intermediate frame, not a duplicate."""
import ctypes
import hashlib
import json
from pathlib import Path
import sys
import vapoursynth as vs
engine = Path(sys.argv[1])
core = vs.core
core.std.LoadPlugin(path=str(engine / 'plugins/librife.dll'))
base = core.std.BlankClip(width=96, height=64, length=2, fpsnum=25, format=vs.RGBS, color=[0, 0, 0])
def moving_rectangle(n, f):
    out = (f[0] if isinstance(f, list) else f).copy()
    left = 16 + n * 8
    for plane in range(3):
        address = out.get_write_ptr(plane).value
        stride = out.get_stride(plane)
        for y in range(64):
            row = (ctypes.c_float * 96).from_address(address + y * stride)
            for x in range(96):
                row[x] = [1, .5, .2][plane] if 16 <= y < 48 and left <= x < left + 24 else 0
    return out
source = core.std.ModifyFrame(base, clips=[base], selector=moving_rectangle)
def measurement(clip, n):
    with clip.get_frame(n) as frame:
        address = frame.get_read_ptr(0).value
        stride = frame.get_stride(0)
        pixels = b''.join(ctypes.string_at(address + y * stride, 96 * 4) for y in range(64))
        row = (ctypes.c_float * 96).from_address(address + 32 * stride)
        weights = [max(0, float(v)) for v in row]
        center = sum(i * v for i, v in enumerate(weights)) / sum(weights)
        return hashlib.sha256(pixels).hexdigest(), center
for model in [23, 70, 72, 73]:
    clip = core.rife.RIFE(source, model=model, factor_num=2, factor_den=1, gpu_id=0, gpu_thread=2, sc=False)
    samples = [measurement(clip, n) for n in [0, 1, 2]]
    report = {'model': model, 'inputFps': 25, 'outputFps': float(clip.fps),
              'centers': [s[1] for s in samples], 'distinctFrames': len({s[0] for s in samples})}
    print(json.dumps(report), flush=True)
    assert report['distinctFrames'] == 3 and samples[0][1] + .1 < samples[1][1] < samples[2][1] - .1, report
