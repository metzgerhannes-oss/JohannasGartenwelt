from pathlib import Path

p=Path('index.html')
s=p.read_text(encoding='utf-8')

viewport='<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">'
meta='''<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="default">
<meta name="apple-mobile-web-app-title" content="Johanna´s Gartenwelt">'''
if 'apple-mobile-web-app-capable' not in s:
    if viewport not in s: raise SystemExit('viewport anchor missing')
    s=s.replace(viewport,meta,1)

old='''@media(max-width:700px){
  body{padding-bottom:calc(76px + env(safe-area-inset-bottom))}
  .wrap{padding-bottom:12px}
  .head{padding-bottom:14px}
  .tabs{position:fixed;left:0;right:0;bottom:0;z-index:4000;margin:0;padding:6px 6px calc(6px + env(safe-area-inset-bottom));display:grid;grid-template-columns:repeat(5,1fr);gap:3px;background:rgba(255,253,249,.94);backdrop-filter:blur(14px);border-top:1px solid var(--line);box-shadow:0 -8px 26px rgba(54,49,44,.10);overflow:visible}
'''
new='''@media(max-width:700px){
  body{padding-bottom:calc(76px + env(safe-area-inset-bottom) + var(--jgw-browser-bottom,0px))}
  .wrap{padding-bottom:12px}
  .head{padding-bottom:14px}
  .tabs{position:fixed;left:0;right:0;bottom:var(--jgw-browser-bottom,0px);z-index:4000;margin:0;padding:6px 6px calc(6px + env(safe-area-inset-bottom));display:grid;grid-template-columns:repeat(5,1fr);gap:3px;background:rgba(255,253,249,.94);backdrop-filter:blur(14px);border-top:1px solid var(--line);box-shadow:0 -8px 26px rgba(54,49,44,.10);overflow:visible}
'''
if old not in s: raise SystemExit('mobile nav CSS anchor missing')
s=s.replace(old,new,1)
s=s.replace('''#globalNotice.toast-message,.undo-toast{bottom:calc(82px + env(safe-area-inset-bottom))}''','''#globalNotice.toast-message,.undo-toast{bottom:calc(82px + env(safe-area-inset-bottom) + var(--jgw-browser-bottom,0px))}''',1)

script='''
<script>
/* iOS/Safari: keep the app navigation above browser chrome when a Home Screen
   shortcut opens as a browser tab instead of standalone. In standalone mode the
   normal safe-area inset is sufficient. */
(function(){
  function standalone(){
    return (window.matchMedia&&window.matchMedia('(display-mode: standalone)').matches)||window.navigator.standalone===true;
  }
  function updateJgwBrowserInset(){
    var px=0;
    if(!standalone()&&window.visualViewport){
      var vv=window.visualViewport;
      px=Math.max(0,Math.round(window.innerHeight-(vv.height+vv.offsetTop)));
      /* Ignore tiny rounding differences; cap pathological keyboard values. */
      if(px<4||px>180)px=0;
    }
    document.documentElement.style.setProperty('--jgw-browser-bottom',px+'px');
  }
  updateJgwBrowserInset();
  window.addEventListener('resize',updateJgwBrowserInset,{passive:true});
  window.addEventListener('orientationchange',function(){setTimeout(updateJgwBrowserInset,120)},{passive:true});
  if(window.visualViewport){
    window.visualViewport.addEventListener('resize',updateJgwBrowserInset,{passive:true});
    window.visualViewport.addEventListener('scroll',updateJgwBrowserInset,{passive:true});
  }
})();
</script>
'''
if '--jgw-browser-bottom' not in s[s.rfind('<script>'):]:
    if '</body>' not in s: raise SystemExit('body close anchor missing')
    s=s.replace('</body>',script+'</body>',1)

p.write_text(s,encoding='utf-8')
print('patched',len(s))
