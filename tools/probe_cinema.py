"""Probe extracted public streams through bundled libmpv without saving video."""
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

inputs = json.loads((verification / 'cinema-native-input.json').read_text(encoding='utf-8'))
selected = os.environ.get('KAZUMI_CINEMA_NATIVE', '').split(',')
if selected != ['']:
    inputs = [item for item in inputs if item['source'] in selected]
reports = []
for item in inputs[:4]:
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
    option('vo', 'null')
    option('ao', 'null')
    option('idle', 'yes')
    option('terminal', 'no')
    option('load-scripts', 'no')
    option('hwdec', 'auto-copy')
    option('http-proxy', os.environ.get('HTTPS_PROXY', ''))
    option('network-timeout', '15')
    option('cache-pause-initial', 'no')
    option('http-header-fields', ','.join(f'{key}: {value}' for key, value in item['headers'].items()))
    assert lib.mpv_initialize(handle) == 0
    args = (c.c_char_p * 4)(b'loadfile', item['url'].encode(), b'replace', None)
    assert lib.mpv_command(handle, args) == 0
    started = time.monotonic()
    try:
        while time.monotonic() - started < 25:
            time.sleep(.5)
            report = {key: property_value(key) for key in ['time-pos', 'video-params/w', 'video-params/h', 'audio-codec']}
            if report['video-params/h'] and report['audio-codec'] and float(report['time-pos'] or 0) > 1:
                break
        report['source'] = item['source']
        report['played'] = bool(report['video-params/h'] and report['audio-codec'] and float(report['time-pos'] or 0) > 1)
        reports.append(report)
        print(json.dumps(report, ensure_ascii=True), flush=True)
    finally:
        lib.mpv_terminate_destroy(handle)
(verification / 'cinema-native-results.json').write_text(json.dumps(reports, ensure_ascii=False, indent=2), encoding='utf-8')
if not any(report['played'] for report in reports):
    raise SystemExit('No public stream played successfully')
