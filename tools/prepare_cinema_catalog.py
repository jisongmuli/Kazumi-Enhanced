import os
import json
from pathlib import Path
root = Path(__file__).resolve().parent.parent
data = json.loads((Path(os.environ.get('KAZUMI_VERIFY_DIR', str(root / 'verification'))) / 'guozhi/sources.json').read_text(encoding='utf-8'))
catalog = []
for source in data:
    item = {key: source[key] for key in ['id', 'name', 'url', 'aliases']}
    if item['id'] == 'guozhi7':
        item['directoryUrl'] = item['url']
        item['url'] = 'https://fdzys.net/'
        item['searchTemplate'] = '/yu-{keyword}-xianguan-de-yingpian-shippin-zhibo'
    catalog.append(item)
(root / 'assets' / 'cinema_sources.json').write_text(json.dumps({
    'directory': 'http://guozhivip.com/mvs.html',
    'checkedAt': '2026-10-12', 'sources': catalog}, ensure_ascii=False, indent=2), encoding='utf-8')
