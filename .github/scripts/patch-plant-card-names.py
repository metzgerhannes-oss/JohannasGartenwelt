from pathlib import Path

shell = Path('jgw-ux-shell.js')
s = shell.read_text(encoding='utf-8')
marker = '/* JGW MOBILE PLANT CARD NAME PRIORITY */'
override = r'''

/* JGW MOBILE PLANT CARD NAME PRIORITY */
var plantCardNameCss=document.createElement("style");
plantCardNameCss.id="jgwPlantCardNamePriority";
plantCardNameCss.textContent=`
@media(max-width:700px){
  #plantList.collection-grid:not(.list-mode),#plantHighlights.collection-strip,#plantFavorites.collection-strip{align-items:stretch}
  .collection-card{display:block!important;min-width:0!important;overflow:hidden!important}
  .collection-card>.collection-photo{display:grid!important;width:100%!important;aspect-ratio:4/3!important;position:relative!important;overflow:hidden!important}
  .collection-card>.collection-card-main{display:block!important;width:100%!important;min-width:0!important}
  .collection-card .collection-body{display:block!important;width:100%!important;min-width:0!important;padding:9px 10px 11px!important}
  .collection-card .collection-name{display:-webkit-box!important;-webkit-box-orient:vertical!important;-webkit-line-clamp:2;white-space:normal!important;overflow:hidden!important;text-overflow:clip!important;overflow-wrap:anywhere!important;word-break:normal!important;min-height:2.36em!important;max-height:2.36em!important;font-size:15px!important;line-height:1.18!important;padding:0!important;margin:0!important}
  .collection-card .collection-latin{white-space:nowrap!important;overflow:hidden!important;text-overflow:ellipsis!important;margin-top:3px!important}
  .collection-card .insect-badge{display:inline-flex!important;align-items:center!important;position:absolute!important;right:7px!important;top:7px!important;left:auto!important;bottom:auto!important;font-size:10px!important;padding:4px 7px!important}
  .collection-card .favorite-plant{display:grid!important;position:absolute!important;left:7px!important;top:7px!important;right:auto!important;bottom:auto!important;width:32px!important;height:32px!important}
  .collection-card .plant-add-one{display:grid!important;position:absolute!important;right:7px!important;bottom:7px!important;top:auto!important;left:auto!important;min-width:38px!important;height:30px!important;padding:0 9px!important}
  .collection-card .plant-quantity-badge{position:absolute!important;left:7px!important;right:auto!important;bottom:7px!important;top:auto!important}
  .collection-card .collection-chips{display:none!important}
}
`;
document.head.appendChild(plantCardNameCss);
/* /JGW MOBILE PLANT CARD NAME PRIORITY */
'''
if marker not in s:
    idx = s.rfind('})();')
    if idx < 0:
        raise SystemExit('Ende von jgw-ux-shell.js nicht gefunden')
    s = s[:idx] + override + s[idx:]
    shell.write_text(s, encoding='utf-8')

nav = Path('jgw-library-nav.js')
n = nav.read_text(encoding='utf-8')
n = n.replace('tag("jgw-ux-shell.js","20260914-1")', 'tag("jgw-ux-shell.js","20260914-2")')
nav.write_text(n, encoding='utf-8')

index = Path('index.html')
i = index.read_text(encoding='utf-8')
i = i.replace('jgw-library-nav.js?v=20260914-2', 'jgw-library-nav.js?v=20260914-3')
index.write_text(i, encoding='utf-8')

assert marker in shell.read_text(encoding='utf-8')
assert 'jgw-ux-shell.js","20260914-2' in nav.read_text(encoding='utf-8')
assert 'jgw-library-nav.js?v=20260914-3' in index.read_text(encoding='utf-8')
