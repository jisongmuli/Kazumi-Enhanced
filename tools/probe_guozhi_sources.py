"""Read the public directory and check its movie-source landing pages."""
import concurrent.futures
import json
from pathlib import Path
import re
import sys
from urllib.parse import urlsplit, urlunsplit
import requests
from lxml import html

verification = Path(sys.argv[1])
output = verification / 'guozhi'
output.mkdir(exist_ok=True)
document = html.fromstring((verification / 'guozhi-mvs.html').read_text(encoding='utf-8'))
anchors = document.xpath('//h5[contains(@class,"fst")]/following-sibling::div[1]//a')
sources = []
for index, anchor in enumerate(anchors[6:]):
    name = anchor.text_content().strip()
    raw = urlsplit(anchor.get('href'))
    url = urlunsplit((raw.scheme, raw.netloc, raw.path or '/', '', ''))
    duplicate = next((item for item in sources if item['url'] == url), None)
    if duplicate:
        duplicate['aliases'].append(name)
        continue
    sources.append({'id': f'guozhi{index+1}', 'name': name, 'url': url, 'aliases': []})

def check(source):
    try:
        response = requests.get(source['url'], timeout=(8, 18), headers={
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36'})
        response.encoding = 'utf-8'
        text = response.text
        (output / (source['id'] + '.html')).write_text(text, encoding='utf-8')
        source.update(status=response.status_code, finalUrl=response.url, bytes=len(response.content))
        tree = html.fromstring(text)
        source['title'] = ' '.join(tree.xpath('//title/text()'))[:100]
        posters = tree.xpath('//a[@href][.//img[@src or @data-original or @data-src] or @data-original or @data-src or @style]')
        source['posterCandidates'] = len(posters)
        source['samples'] = [
            {'href': anchor.get('href'), 'class': anchor.get('class'), 'title': anchor.get('title'),
             'images': [{key: image.get(key) for key in ['src', 'alt', 'data-original', 'data-src']} for image in anchor.xpath('.//img')[:1]],
             'style': anchor.get('style'), 'original': anchor.get('data-original')}
            for anchor in posters[:5]
        ]
    except Exception as error:
        source.update(status='error', error=str(error)[:180])
    print(json.dumps({key:source.get(key) for key in ['id','name','status','finalUrl','bytes','title','posterCandidates']}, ensure_ascii=True), flush=True)
    return source

with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    checked = list(pool.map(check, sources))
(output / 'sources.json').write_text(json.dumps(checked, ensure_ascii=False, indent=2), encoding='utf-8')
