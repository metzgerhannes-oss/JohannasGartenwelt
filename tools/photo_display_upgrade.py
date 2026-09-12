from pathlib import Path

p=Path('index.html')
s=p.read_text(encoding='utf-8')

css=r'''

/* JGW PHOTO DISPLAY UPGRADE */
.collection-photo,.nature-card-photo,.plantphoto,.photo-preview,.detail-hero{
  position:relative;
  isolation:isolate;
  background:#e9e3da;
}
.collection-photo.has-photo-bg::before,.nature-card-photo.has-photo-bg::before,.plantphoto.has-photo-bg::before,.photo-preview.has-photo-bg::before,.detail-hero.has-photo-bg::before{
  content:"";
  position:absolute;
  inset:-12%;
  z-index:0;
  background-image:var(--photo-bg);
  background-position:center;
  background-size:cover;
  filter:blur(18px) brightness(.80) saturate(.82);
  transform:scale(1.08);
  opacity:.72;
  pointer-events:none;
}
.collection-photo img,.nature-card-photo img,.plantphoto img,.photo-preview img{
  width:100%;
  height:100%;
  object-fit:contain!important;
  object-position:center;
  position:relative;
  z-index:1;
  background:transparent;
}
.detail-hero.has-photo-bg{
  aspect-ratio:auto!important;
  min-height:180px;
  max-height:none;
  display:flex;
  align-items:center;
  justify-content:center;
  padding:0;
}
.detail-hero.has-photo-bg img{
  width:auto!important;
  height:auto!important;
  max-width:100%;
  max-height:60svh;
  object-fit:contain!important;
  object-position:center;
  position:relative;
  z-index:1;
  display:block;
}
@media(max-width:760px){
  .detail-hero.has-photo-bg{min-height:150px}
  .detail-hero.has-photo-bg img{max-height:58svh}
}
/* /JGW PHOTO DISPLAY UPGRADE */
'''

if 'JGW PHOTO DISPLAY UPGRADE' not in s:
    i=s.find('</style>')
    if i<0: raise SystemExit('style close not found')
    s=s[:i]+css+s[i:]

js=r'''
<script>
(function(){
  "use strict";
  var selector=".collection-photo,.nature-card-photo,.plantphoto,.photo-preview,.detail-hero";
  function photoBgValue(src){
    return 'url("'+String(src||"").replace(/\\/g,"\\\\").replace(/"/g,"%22")+'")';
  }
  function enhancePhotoFrames(root){
    var scope=root&&root.querySelectorAll?root:document;
    scope.querySelectorAll(selector).forEach(function(frame){
      var img=frame.querySelector("img");
      if(!img||!img.getAttribute("src")){
        frame.classList.remove("has-photo-bg");
        frame.style.removeProperty("--photo-bg");
        return;
      }
      frame.classList.add("has-photo-bg");
      frame.style.setProperty("--photo-bg",photoBgValue(img.currentSrc||img.src||img.getAttribute("src")));
    });
  }
  function scheduleEnhance(){
    if(scheduleEnhance.raf)return;
    scheduleEnhance.raf=requestAnimationFrame(function(){scheduleEnhance.raf=0;enhancePhotoFrames(document)});
  }
  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",scheduleEnhance,{once:true});else scheduleEnhance();
  new MutationObserver(scheduleEnhance).observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:["src"]});
  window.addEventListener("load",scheduleEnhance,{once:true});
})();
</script>
'''

if 'function enhancePhotoFrames' not in s:
    i=s.rfind('</body>')
    if i<0: raise SystemExit('body close not found')
    s=s[:i]+js+s[i:]

p.write_text(s,encoding='utf-8')
print('patched',len(s))
