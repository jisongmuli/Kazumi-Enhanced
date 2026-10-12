import os
"""Add researched sources without replacing any existing source or URL."""
import json
from pathlib import Path

repo = Path(__file__).resolve().parent.parent
verify = Path(os.environ.get('KAZUMI_VERIFY_DIR', str(repo / 'verification'))) / 'sources-extra'
catalog_path = repo / 'assets/cinema_sources.json'
catalog = json.loads(catalog_path.read_text(encoding='utf-8'))
existing = {source['url'].rstrip('/') for source in catalog['sources']}
resource_url = 'https://github.com/laoma528/awesome-zhuiju-free/blob/main/resources/resources.json'
resources = json.loads((verify / 'resources.json').read_text(encoding='utf-8'))['resources']
ids = ['ai-movie', 'nfyingshi', 'ppnix', 'guangsu-yingshi', 'juzong', 'jianyunys',
       'pianku', '66-dapianwang', 'didahd', 'zhuiying', 'kxyy', 'dhvideo',
       'kanmovie-com-34', 'skr-skr1-cc-9']
new = []
for item in resources:
    if item['id'] in ids:
        new.append({'id': 'extra_' + item['id'], 'name': item['name'],
                    'url': item['url'], 'aliases': [], 'discoveredFrom': resource_url})
new += [{'id': 'hongguo_official', 'name': '红果短剧（官方）',
         'url': 'https://hongguoduanju.com/', 'aliases': [],
         'searchTemplate': '/search/{keyword}',
         'discoveredFrom': 'https://www.novelquickapp.com/'}]
for suffix in ['cam', 'lat', 'bid', 'dev']:
    new.append({'id': 'libvio_' + suffix, 'name': 'LIBVIO（' + suffix + '入口）',
                'url': 'https://www.libvio.' + suffix + '/', 'aliases': [],
                'parentId': 'guozhi11', 'discoveredFrom': 'https://libvio.lol/'})
new += [
    {'id': 'fdz_com', 'name': '饭搭子影视（com入口）', 'url': 'https://fdzys.com/',
     'searchTemplate': '/yu-{keyword}-xianguan-de-yingpian-shippin-zhibo',
     'aliases': [], 'parentId': 'guozhi7', 'discoveredFrom': 'https://fdzys666.xyz/'},
    {'id': 'fdz_release', 'name': '饭搭子影视（地址公告）', 'url': 'https://fdzys666.xyz/',
     'aliases': [], 'parentId': 'guozhi7', 'discoveredFrom': 'http://guozhivip.com/mvs.html'},
    {'id': 'libvio_release', 'name': 'LIBVIO（地址公告）', 'url': 'https://libvio.lol/',
     'aliases': [], 'parentId': 'guozhi11', 'discoveredFrom': 'https://libvio.lol/'},
    {'id': 'keke_20', 'name': '可可影视（keke20入口）', 'url': 'https://www.keke20.com/',
     'aliases': [], 'parentId': 'guozhi17', 'discoveredFrom': 'https://dl.kekedy.app/'},
    {'id': 'keke_release', 'name': '可可影视（地址公告）', 'url': 'https://dl.kekedy.app/',
     'aliases': [], 'parentId': 'guozhi17', 'discoveredFrom': 'https://dl.kekedy.app/'},
]
for item in new:
    if item['url'].rstrip('/') in existing:
        continue
    catalog['sources'].append(item)
    existing.add(item['url'].rstrip('/'))
catalog['checkedAt'] = '2026-10-12'
catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('Catalog entries:', len(catalog['sources']))
