from pathlib import Path
p=Path('index.html')
s=p.read_text(encoding='utf-8')

css=r'''

/* JGW MOBILE USABILITY */
@media(max-width:700px){
  .nature-tab,.plant-filter,.library-filter,.view-toggle button{min-height:44px;display:inline-flex;align-items:center;justify-content:center}
  .plant-sort,.appearance-row select{min-height:44px}
  details:not(.plant-more)>summary{min-height:44px;display:flex;align-items:center;padding:9px 2px;touch-action:manipulation}
  .practice-item,.habitat-item{min-height:48px;align-items:center}
  .practice-item input,.habitat-item input{width:22px;height:22px;min-width:22px}
  .leaflet-touch .leaflet-bar a,.leaflet-control-zoom a,.leaflet-draw-toolbar a{width:44px!important;height:44px!important;line-height:44px!important}
  #plantForm>.actions,#habitatForm>.actions,#animalForm>.actions{display:grid;grid-template-columns:1fr;gap:8px;width:100%}
  #plantForm>.actions .btn,#habitatForm>.actions .btn,#animalForm>.actions .btn{width:100%}
  .library-toolbar>.actions{width:100%;display:grid;grid-template-columns:minmax(0,1fr) auto;align-items:center}
  .library-toolbar>.actions .library-search{min-width:0;max-width:none;width:100%}
  .plant-toolbar{gap:8px}.plant-toolbar .view-toggle{min-height:44px}.plant-toolbar .plant-sort{flex:1;max-width:none;min-width:132px}
}
@media(max-width:420px){
  .brand{flex-wrap:wrap;gap:8px}
  .brand>div:first-child{min-width:0;max-width:100%}
  .brandtools{width:100%;justify-content:flex-end;gap:6px;flex-wrap:nowrap}
  .head{padding-top:14px}
  .library-toolbar>.actions{grid-template-columns:1fr}
  .library-toolbar>.actions .btn{width:100%}
  #naturePlantsPane>.box>.topline>.actions{width:100%}
  #naturePlantsPane>.box>.topline>.actions .plant-search{width:100%;max-width:none}
  #naturePlantsPane>.box>.topline>.actions .btn{flex:1}
}
@media(max-width:360px){
  .tabs{gap:1px;padding-left:3px;padding-right:3px}
  .tabs .tab{font-size:9.2px;padding-left:1px;padding-right:1px}
  .tabs .navicon{width:19px;height:19px}.tabs .navicon svg{width:19px;height:19px}
  .brand h1{font-size:19px}
}
/* /JGW MOBILE USABILITY */
'''
if '/* JGW MOBILE USABILITY */' not in s:
    s=s.replace('\n</style>',css+'\n</style>',1)

old=r'''(function(){
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
})();'''
new=r'''(function(){
  function standalone(){
    return (window.matchMedia&&window.matchMedia('(display-mode: standalone)').matches)||window.navigator.standalone===true;
  }
  function isIOS(){
    var ua=navigator.userAgent||"";
    return /iPad|iPhone|iPod/i.test(ua)||(navigator.platform==="MacIntel"&&navigator.maxTouchPoints>1);
  }
  function keyboardOpen(){
    if(!window.visualViewport)return false;
    var ae=document.activeElement,editing=ae&&/^(INPUT|TEXTAREA|SELECT)$/.test(ae.tagName);
    return !!editing&&window.visualViewport.height<window.innerHeight*.76;
  }
  function updateJgwBrowserInset(){
    var px=0;
    if(!standalone()){
      if(window.visualViewport){
        var vv=window.visualViewport;
        px=Math.max(0,Math.round(window.innerHeight-(vv.height+vv.offsetTop)));
        if(px<4||px>180)px=0;
      }
      /* iOS Safari often overlays its bottom toolbar without reporting its height
         through VisualViewport. Keep a conservative touch-safe reserve in browser mode. */
      if(isIOS()&&!keyboardOpen())px=Math.max(px,88);
    }
    document.documentElement.style.setProperty('--jgw-browser-bottom',px+'px');
    document.body.classList.toggle('jgw-keyboard-open',keyboardOpen());
  }
  updateJgwBrowserInset();
  window.addEventListener('resize',updateJgwBrowserInset,{passive:true});
  window.addEventListener('orientationchange',function(){setTimeout(updateJgwBrowserInset,160)},{passive:true});
  document.addEventListener('focusin',function(){setTimeout(updateJgwBrowserInset,80)},{passive:true});
  document.addEventListener('focusout',function(){setTimeout(updateJgwBrowserInset,180)},{passive:true});
  if(window.visualViewport){
    window.visualViewport.addEventListener('resize',updateJgwBrowserInset,{passive:true});
    window.visualViewport.addEventListener('scroll',updateJgwBrowserInset,{passive:true});
  }
})();'''
if old not in s:
    raise SystemExit('old iOS inset block not found')
s=s.replace(old,new,1)

# Hide fixed nav while the on-screen keyboard is open; it otherwise competes for scarce space.
keyboard_css='''\n@media(max-width:700px){body.jgw-keyboard-open .tabs{transform:translateY(130%);pointer-events:none}body.jgw-keyboard-open{padding-bottom:12px}}\n'''
if 'body.jgw-keyboard-open .tabs' not in s:
    s=s.replace('/* /JGW MOBILE USABILITY */',keyboard_css+'/* /JGW MOBILE USABILITY */',1)

p.write_text(s,encoding='utf-8')
print('patched',len(s))
