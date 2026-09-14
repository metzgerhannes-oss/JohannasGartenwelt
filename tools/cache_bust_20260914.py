from pathlib import Path

p=Path('index.html')
s=p.read_text(encoding='utf-8')
old='<script src="./jgw-library-nav.js?v=20260912-runtime3"></script>'
new='<script src="./jgw-library-nav.js?v=20260914-1"></script>'
if s.count(old)!=1:
    raise RuntimeError(f'Expected one old module loader include, found {s.count(old)}')
p.write_text(s.replace(old,new,1),encoding='utf-8')
print('Updated module-loader cache key')
