import os
import json
from pathlib import Path
from lxml import html
import requests
directory = Path(os.environ.get('KAZUMI_VERIFY_DIR', str(Path(__file__).resolve().parent.parent / 'verification')))
for source in json.loads((directory / 'cinema-live-results.json').read_text(encoding='utf-8')):
    if source['id'] not in ['guozhi1', 'guozhi15', 'guozhi7']:
        continue
    if source['id'] == 'guozhi7':
        tree = html.fromstring((directory / 'guozhi/fdz.txt').read_text(encoding='utf-8'))
        anchors = tree.xpath('//a[@href][.//img or @data-original]')
        print('fdz posters', [html.tostring(a, encoding='unicode')[:350] for a in anchors[:8]])
        continue
    response = requests.get(source['url'], timeout=15)
    response.encoding = 'utf-8'
    (directory / 'guozhi' / (source['id'] + '-detail.html')).write_text(response.text, encoding='utf-8')
    tree = html.fromstring(response.text)
    anchors = tree.xpath('//a[contains(@href,"play") or contains(@href,"bf")]')
    print(source['id'], response.status_code, 'play', [html.tostring(a, encoding='unicode')[:400] for a in anchors[:3]])
    print('parents', [html.tostring(a.getparent(), encoding='unicode')[:500] for a in anchors[:2]])
