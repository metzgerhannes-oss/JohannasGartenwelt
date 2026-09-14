(function(){
"use strict";
/* Stable entrypoint referenced by index.html. The split files load synchronously before the next app script. */
if(window.__jgwUxBundleLoader)return;window.__jgwUxBundleLoader=true;
var base=(document.currentScript&&document.currentScript.src)||location.href;
var root=base.slice(0,base.lastIndexOf("/")+1);
function tag(file,version){return '<script src="'+root+file+'?v='+version+'"></'+'script>'}
document.write(tag("jgw-ux-shell.js","20260914-2")+tag("jgw-library-v4.js","20260914-2")+tag("jgw-ux-patch.js","20260914-1")+tag("jgw-photo-storage-v2.js","20260914-2"));

function installPlantCardFix(){
  if(document.getElementById("jgwPlantCardFinalFix"))return;
  var css=document.createElement("style");
  css.id="jgwPlantCardFinalFix";
  css.textContent=`
@media(max-width:700px){
  #plantList.collection-grid:not(.list-mode)>.collection-card,
  #plantHighlights>.collection-card,
  #plantFavorites>.collection-card{
    display:flex!important;
    flex-direction:column!important;
    align-items:stretch!important;
    min-width:0!important;
    overflow:hidden!important;
  }
  #plantList.collection-grid:not(.list-mode)>.collection-card>.collection-photo,
  #plantHighlights>.collection-card>.collection-photo,
  #plantFavorites>.collection-card>.collection-photo{
    display:block!important;
    width:100%!important;
    flex:0 0 auto!important;
    aspect-ratio:4/3!important;
    min-width:0!important;
    position:relative!important;
    overflow:hidden!important;
  }
  #plantList.collection-grid:not(.list-mode)>.collection-card>.collection-card-main,
  #plantHighlights>.collection-card>.collection-card-main,
  #plantFavorites>.collection-card>.collection-card-main{
    display:block!important;
    width:100%!important;
    min-width:0!important;
    flex:0 0 auto!important;
  }
  #plantList.collection-grid:not(.list-mode) .collection-body,
  #plantHighlights .collection-body,
  #plantFavorites .collection-body{
    display:block!important;
    width:100%!important;
    min-width:0!important;
    padding:10px 11px 12px!important;
  }
  #plantList.collection-grid:not(.list-mode) .collection-name,
  #plantHighlights .collection-name,
  #plantFavorites .collection-name{
    display:-webkit-box!important;
    -webkit-box-orient:vertical!important;
    -webkit-line-clamp:2!important;
    white-space:normal!important;
    overflow:hidden!important;
    text-overflow:clip!important;
    overflow-wrap:anywhere!important;
    min-height:2.42em!important;
    max-height:2.42em!important;
    font-size:16px!important;
    line-height:1.21!important;
    padding:0!important;
    margin:0!important;
    color:var(--forest-dark)!important;
  }
  #plantList.collection-grid:not(.list-mode) .collection-card-name-mobile,
  #plantHighlights .collection-card-name-mobile,
  #plantFavorites .collection-card-name-mobile{display:none!important}
  #plantList.collection-grid:not(.list-mode) .collection-photo>.collection-card-main,
  #plantHighlights .collection-photo>.collection-card-main,
  #plantFavorites .collection-photo>.collection-card-main{height:100%!important}
  #plantList.collection-grid:not(.list-mode) .collection-photo img,
  #plantHighlights .collection-photo img,
  #plantFavorites .collection-photo img{width:100%!important;height:100%!important;object-fit:cover!important}
}
`;
  document.head.appendChild(css);
}

function checkForNewBuild(){
  try{
    var currentScript=Array.from(document.scripts).find(function(s){return /jgw-library-nav\.js/i.test(s.src||"")});
    var currentVersion="";
    try{currentVersion=currentScript?new URL(currentScript.src).searchParams.get("v")||"":""}catch(e){}
    fetch(root+"index.html?jgw_update="+Date.now(),{cache:"no-store"})
      .then(function(r){return r.ok?r.text():""})
      .then(function(t){
        var m=t.match(/jgw-library-nav\.js\?v=([^\"'&<\s]+)/i);
        var latest=m&&m[1]||"";
        if(!latest||!currentVersion||latest===currentVersion)return;
        var guard="jgw-reload-"+latest;
        if(sessionStorage.getItem(guard))return;
        sessionStorage.setItem(guard,"1");
        var u=new URL(location.href);
        u.searchParams.set("v",latest);
        location.replace(u.toString());
      }).catch(function(){});
  }catch(e){}
}

setTimeout(installPlantCardFix,0);
setTimeout(checkForNewBuild,1200);
window.addEventListener("pageshow",function(){setTimeout(function(){installPlantCardFix();checkForNewBuild()},250)});
document.addEventListener("visibilitychange",function(){if(document.visibilityState==="visible")setTimeout(checkForNewBuild,300)});
})();
