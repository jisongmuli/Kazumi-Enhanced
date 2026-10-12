"""Stream a live YouTube extraction through the bundled libmpv without saving media.

Usage: python tools/probe_youtube.py <video_engine_dir> <verification_dir>
The explicitly invoked Flutter live test writes youtube-native-input.json first.
"""
import ctypes as c
import json
import os
from pathlib import Path
import sys
import time

engine, verification = map(Path, sys.argv[1:3])
lib = c.CDLL(str(engine / 'libmpv-2.dll'))
lib.mpv_create.restype = c.c_void_p
for name, args, result in [
    ('mpv_initialize', [c.c_void_p], c.c_int),
    ('mpv_set_option_string', [c.c_void_p, c.c_char_p, c.c_char_p], c.c_int),
    ('mpv_set_property_string', [c.c_void_p, c.c_char_p, c.c_char_p], c.c_int),
    ('mpv_get_property_string', [c.c_void_p, c.c_char_p], c.c_void_p),
    ('mpv_command', [c.c_void_p, c.POINTER(c.c_char_p)], c.c_int),
    ('mpv_free', [c.c_void_p], None),
    ('mpv_terminate_destroy', [c.c_void_p], None),
]:
    func = getattr(lib, name)
    func.argtypes, func.restype = args, result

qualities = json.loads((verification / 'youtube-native-input.json').read_text(encoding='utf-8'))['qualities']
handle = lib.mpv_create()

def option(name, value):
    assert lib.mpv_set_option_string(handle, name.encode(), value.encode()) == 0, name

def property_value(name):
    pointer = lib.mpv_get_property_string(handle, name.encode())
    if not pointer:
        return None
    text = c.string_at(pointer).decode('utf-8', 'replace')
    lib.mpv_free(pointer)
    return text

def command(*args):
    values = (c.c_char_p * (len(args) + 1))(*[arg.encode('utf-8') for arg in args], None)
    assert lib.mpv_command(handle, values) == 0, args[0]

option('vo', 'null')
option('ao', 'null')
option('idle', 'yes')
option('terminal', 'no')
option('load-scripts', 'no')
option('hwdec', 'auto-copy')
option('log-file', str(verification / 'youtube-native.log'))
option('http-proxy', os.environ.get('HTTPS_PROXY', ''))
option('network-timeout', '15')
option('cache-secs', '10')
option('demuxer-readahead-secs', '5')
option('cache-pause-initial', 'no')
assert lib.mpv_initialize(handle) == 0
reports = []
try:
    for height, start, paused in [(360, 0, False), (1080, 30, False), (2160, 60, True)]:
        quality = next(item for item in qualities if item['height'] == height)
        command('stop')
        command('change-list', 'audio-files', 'clr', '')
        if quality['audioUrl']:
            command('change-list', 'audio-files', 'append', quality['audioUrl'])
        headers = ','.join(f'{key}: {value}' for key, value in quality['headers'].items())
        assert lib.mpv_set_property_string(handle, b'http-header-fields', headers.encode()) == 0
        assert lib.mpv_set_property_string(handle, b'pause', b'yes' if paused else b'no') == 0
        assert lib.mpv_set_property_string(handle, b'start', str(start).encode()) == 0
        command('loadfile', quality['videoUrl'], 'replace')
        started = time.monotonic()
        while time.monotonic() - started < 40:
            time.sleep(1)
            result = {name: property_value(name) for name in [
                'time-pos', 'video-params/h', 'audio-codec', 'pause', 'idle-active', 'duration']}
            if result['video-params/h'] == str(height) and result['audio-codec']:
                if paused or float(result['time-pos'] or 0) > start + 1:
                    break
        result.update(requestedHeight=height, requestedStart=start, requestedPaused=paused)
        reports.append(result)
        print(json.dumps(result), flush=True)
finally:
    lib.mpv_terminate_destroy(handle)
(verification / 'youtube-native-results.json').write_text(json.dumps(reports, indent=2), encoding='utf-8')
assert all(item['video-params/h'] == str(item['requestedHeight']) and item['audio-codec'] for item in reports)
assert abs(float(reports[2]['time-pos']) - 60) < 2 and reports[2]['pause'] == 'yes'
