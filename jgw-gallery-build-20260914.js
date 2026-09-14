(function(){
"use strict";
if(window.__jgwGalleryBuild20260914)return;window.__jgwGalleryBuild20260914=true;
var BUILD="2026.09.14-01";
function mount(){
  var wrap=document.getElementById("plantCollectionWrap");
  if(!wrap)return;
  var badge=document.getElementById("jgwGalleryBuildBadge");
  if(!badge){
    badge=document.createElement("div");
    badge.id="jgwGalleryBuildBadge";
    badge.setAttribute("aria-label","Galerie-Version "+BUILD);
    badge.textContent="Galerie-Version: "+BUILD;
    badge.style.cssText="margin:12px 0 8px;padding:7px 10px;border:1px solid #c8a56a;border-radius:10px;background:#fff3cf;color:#6d5730;font:800 12px/1.2 -apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;letter-spacing:.02em;text-align:center;";
    wrap.insertBefore(badge,wrap.firstChild);
  }
  badge.textContent="Galerie-Version: "+BUILD;
}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",mount,{once:true});else mount();
new MutationObserver(mount).observe(document.documentElement,{childList:true,subtree:true});
window.addEventListener("pageshow",mount);
})();
