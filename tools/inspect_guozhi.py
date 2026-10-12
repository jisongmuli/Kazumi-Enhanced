import os
from pathlib import Path
from lxml import html
import requests
import re
import json
directory = Path(os.environ.get('KAZUMI_VERIFY_DIR', str(Path(__file__).resolve().parent.parent / 'verification'))) / 'guozhi'
for source in json.loads((directory / 'sources.json').read_text(encoding='utf-8')):
    if source.get('posterCandidates', 0) < 10:
        continue
    tree = html.fromstring((directory / (source['id'] + '.html')).read_text(encoding='utf-8'))
    print(source['id'], source['url'], flush=True)
    print('forms', [html.tostring(x, encoding='unicode')[:500] for x in tree.xpath('//form')[:2]])
    anchors = tree.xpath('//a[@href][.//img or @data-original or contains(@style,"background")]')
    print('cards', [html.tostring(x, encoding='unicode')[:650] for x in anchors[:2]])
for key, url in [('kanjujs', 'https://kanju3.com/assets/main-DupXbhqc.js'),
                 ('wasujs', 'https://www.wasu.cn/1.2.12.1/assets/js/index-CNpzdZut.js'),
                 ('fdz', 'https://fdzys.net')]:
    try:
        response = requests.get(url, timeout=18)
        response.encoding = 'utf-8'
        (directory / (key + '.txt')).write_text(response.text, encoding='utf-8')
        endpoints = list(dict.fromkeys(re.findall(r'https?[^\s"\x27<>\\`]{5,160}', response.text)))
        print(key, response.status_code, len(response.content), 'urls', endpoints[:25])
    except Exception as error:
        print(key, str(error)[:100])
