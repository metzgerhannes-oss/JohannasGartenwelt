from pathlib import Path
import re

p=Path('index.html')
s=p.read_text(encoding='utf-8')
css_marker='/* JGW PLANT CARD FULL NAME FOOTER */'
if css_marker not in s:
    css='''\n/* JGW PLANT CARD FULL NAME FOOTER */\n.collection-card-name-mobile{display:none}\n@media(max-width:700px){\n  .collection-card{flex-wrap:wrap!important}\n  .collection-card-name-mobile{\n    display:-webkit-box!important;\n    -webkit-box-orient:vertical!important;\n    -webkit-line-clamp:2;\n    grid-column:1/-1!important;\n    flex:0 0 100%!important;\n    width:100%!important;\n    min-width:0!important;\n    min-height:50px!important;\n    max-height:58px!important;\n    margin:0!important;\n    padding:8px 10px 10px!important;\n    border:0!important;\n    border-top:1px solid #eee3d5!important;\n    background:#fffdf9!important;\n    color:var(--forest-dark)!important;\n    font:700 15px/1.22 Georgia,\"Times New Roman\",serif!important;\n    text-align:left!important;\n    white-space:normal!important;\n    overflow:hidden!important;\n    overflow-wrap:anywhere!important;\n  }\n  .collection-card .collection-body .collection-name{display:none!important}\n}\n/* /JGW PLANT CARD FULL NAME FOOTER */\n'''
    # append to first style block, so the rule is part of the HTML itself
    first_close=s.find('</style>')
    if first_close<0:
        raise SystemExit('style block not found')
    s=s[:first_close]+css+s[first_close:]

if 'collection-card-name-mobile plantOpen' not in s:
    start=s.find('function plantCardHtml(p,feature){')
    end=s.find('\nfunction plantListRowHtml', start)
    if start<0 or end<0:
        raise SystemExit('plantCardHtml not found')
    part=s[start:end]
    old="</div></button></article>'}"
    if old not in part:
        raise SystemExit('plantCardHtml ending not found')
    new='</div></button><button class="collection-card-name-mobile plantOpen" data-id="\'+p.id+\'" type="button" aria-label="\'+esc(p.name)+\' öffnen">\'+esc(p.name)+\'</button></article>\'}'
    part=part.replace(old,new,1)
    s=s[:start]+part+s[end:]

# visible build marker and cache buster on the stable bundle entrypoint
s=s.replace('jgw-library-nav.js?v=20260914-3','jgw-library-nav.js?v=20260914-4')

p.write_text(s,encoding='utf-8')
assert css_marker in s
assert 'collection-card-name-mobile plantOpen' in s
assert 'jgw-library-nav.js?v=20260914-4' in s
