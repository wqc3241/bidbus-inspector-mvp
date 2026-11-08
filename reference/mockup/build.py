#!/usr/bin/env python3
"""Build dist/internal-mvp.html from src/template.html.

Fills three markers in the template:
  /*__QL__*/null   the inspection question list (data/question-list.json, the MVP copy)
  /*__LU__*/{}     the icon map (assets/lu.js, Lucide paths taken from the condition report page)
  <!--__LOGO__-->  the Bidbus logo (assets/logo.html)

Usage: python3 build.py   (run from this folder)
"""
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
# The question list: data/question-list.json. Change it there.
QL = os.path.join(HERE, '..', '..', 'data', 'question-list.json')


def main():
    tpl = open(os.path.join(HERE, 'src', 'template.html'), encoding='utf-8').read()
    ql = json.load(open(QL, encoding='utf-8'))
    dp = ql.get('damage_places') or {}
    if not dp.get('sections'):
        raise SystemExit('question list: damage_places missing (the damage photo place map)')
    ql_js = json.dumps(ql, ensure_ascii=False, separators=(',', ':')).replace('</', '<\\/')
    lu_src = open(os.path.join(HERE, 'assets', 'lu.js'), encoding='utf-8').read()
    m = re.search(r'=\s*(\{[\s\S]*\})\s*;?\s*$', lu_src)
    if not m:
        raise SystemExit('assets/lu.js: icon map not found')
    logo = open(os.path.join(HERE, 'assets', 'logo.html'), encoding='utf-8').read().strip()
    logo = re.sub(r'<span class="crt">.*?</span>', '', logo)  # keep the mark only
    for marker in ('/*__QL__*/null', '/*__LU__*/{}', '<!--__LOGO__-->'):
        if tpl.count(marker) != 1:
            raise SystemExit('template: marker %s found %d times' % (marker, tpl.count(marker)))
    out = tpl.replace('/*__QL__*/null', ql_js).replace('/*__LU__*/{}', m.group(1)).replace('<!--__LOGO__-->', logo)
    os.makedirs(HERE, exist_ok=True)
    path = os.path.join(HERE, 'internal-mvp.html')
    open(path, 'w', encoding='utf-8').write(out)
    print('wrote %s (%d KB, %d questions)' % (path, len(out.encode('utf-8')) // 1024, len(ql['items'])))


if __name__ == '__main__':
    main()
