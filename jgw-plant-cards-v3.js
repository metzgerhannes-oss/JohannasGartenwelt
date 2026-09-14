(function(){
"use strict";
if(window.__jgwPlantCardsV3)return;window.__jgwPlantCardsV3=true;

var css=document.createElement("style");
css.id="jgwPlantCardsV3Style";
css.textContent=`
@media(max-width:700px){
  #naturePlantsPane .collection-card{
    display:flex!important;
    flex-direction:column!important;
    align-items:stretch!important;
    min-width:0!important;
    overflow:hidden!important;
  }
  #naturePlantsPane .collection-card>.collection-photo{
    display:block!important;
    width:100%!important;
    max-width:none!important;
    height:auto!important;
    aspect-ratio:4/3!important;
    position:relative!important;
    overflow:hidden!important;
    flex:none!important;
  }
  #naturePlantsPane .collection-card>.collection-photo>.collection-card-main{
    display:block!important;
    width:100%!important;
    height:100%!important;
    padding:0!important;
  }
  #naturePlantsPane .collection-card>.collection-photo img,
  #naturePlantsPane .collection-card>.collection-photo .collection-no-photo{
    display:block!important;
    width:100%!important;
    height:100%!important;
    object-fit:cover!important;
  }
  #naturePlantsPane .collection-card>.collection-card-main{
    display:block!important;
    width:100%!important;
    min-width:0!important;
    flex:none!important;
  }
  #naturePlantsPane .collection-card .collection-body{
    display:block!important;
    width:100%!important;
    min-width:0!important;
    padding:10px 11px 12px!important;
  }
  #naturePlantsPane .collection-card .collection-name{
    display:-webkit-box!important;
    -webkit-box-orient:vertical!important;
    -webkit-line-clamp:2!important;
    white-space:normal!important;
    overflow:hidden!important;
    text-overflow:clip!important;
    overflow-wrap:anywhere!important;
    min-height:2.4em!important;
    max-height:2.4em!important;
    font-size:15px!important;
    line-height:1.2!important;
    padding:0!important;
    margin:0!important;
  }
  #naturePlantsPane .collection-card .collection-latin{
    margin-top:4px!important;
    min-height:0!important;
    font-size:10px!important;
    white-space:nowrap!important;
    overflow:hidden!important;
    text-overflow:ellipsis!important;
  }
  #naturePlantsPane .collection-card .collection-area{
    margin-top:4px!important;
    font-size:10px!important;
    white-space:nowrap!important;
    overflow:hidden!important;
    text-overflow:ellipsis!important;
  }
  #naturePlantsPane .collection-card .collection-status{
    margin-top:6px!important;
    font-size:10px!important;
  }
  #naturePlantsPane .collection-card .collection-card-name-mobile{
    display:none!important;
  }
  #naturePlantsPane .collection-card .insect-badge{
    display:inline-flex!important;
    align-items:center!important;
    position:absolute!important;
    right:7px!important;
    top:7px!important;
    left:auto!important;
    bottom:auto!important;
    padding:4px 7px!important;
    font-size:10px!important;
  }
  #naturePlantsPane .collection-card .favorite-plant{
    display:grid!important;
    position:absolute!important;
    left:7px!important;
    top:7px!important;
    right:auto!important;
    bottom:auto!important;
    width:34px!important;
    height:34px!important;
  }
  #naturePlantsPane .collection-card .plant-add-one{
    display:grid!important;
    position:absolute!important;
    right:7px!important;
    bottom:7px!important;
    top:auto!important;
    left:auto!important;
    min-width:40px!important;
    height:32px!important;
    padding:0 9px!important;
  }
  #naturePlantsPane .collection-card .plant-quantity-badge{
    display:grid!important;
    position:absolute!important;
    left:7px!important;
    right:auto!important;
    bottom:7px!important;
    top:auto!important;
  }
  #naturePlantsPane .collection-card .collection-chips{display:none!important}
}
`;
document.head.appendChild(css);

function force(el,prop,val){if(el)el.style.setProperty(prop,val,"important")}
function patchCard(card){
  if(!card||window.innerWidth>700)return;
  force(card,"display","flex");
  force(card,"flex-direction","column");
  force(card,"align-items","stretch");
  force(card,"min-width","0");
  force(card,"overflow","hidden");

  var photo=card.querySelector(":scope > .collection-photo");
  if(photo){
    force(photo,"display","block");
    force(photo,"width","100%");
    force(photo,"max-width","none");
    force(photo,"height","auto");
    force(photo,"aspect-ratio","4 / 3");
    force(photo,"position","relative");
    force(photo,"overflow","hidden");
    force(photo,"flex","none");
    var photoButton=photo.querySelector(":scope > .collection-card-main");
    if(photoButton){force(photoButton,"display","block");force(photoButton,"width","100%");force(photoButton,"height","100%");force(photoButton,"padding","0")}
    var img=photo.querySelector("img");
    if(img){force(img,"display","block");force(img,"width","100%");force(img,"height","100%");force(img,"object-fit","cover")}
  }

  var bodyButton=Array.from(card.children).find(function(x){return x.classList&&x.classList.contains("collection-card-main")});
  if(bodyButton){force(bodyButton,"display","block");force(bodyButton,"width","100%");force(bodyButton,"min-width","0");force(bodyButton,"flex","none")}

  var body=card.querySelector(".collection-body");
  if(body){force(body,"display","block");force(body,"width","100%");force(body,"min-width","0");force(body,"padding","10px 11px 12px")}
  var name=card.querySelector(".collection-name");
  if(name){force(name,"display","-webkit-box");force(name,"white-space","normal");force(name,"overflow","hidden");force(name,"text-overflow","clip");force(name,"overflow-wrap","anywhere");force(name,"min-height","2.4em");force(name,"max-height","2.4em");force(name,"font-size","15px");force(name,"line-height","1.2");force(name,"padding","0");force(name,"margin","0");name.style.setProperty("-webkit-box-orient","vertical","important");name.style.setProperty("-webkit-line-clamp","2","important")}
  var duplicate=card.querySelector(".collection-card-name-mobile");if(duplicate)force(duplicate,"display","none");
}
function patchAll(){if(window.innerWidth>700)return;document.querySelectorAll("#naturePlantsPane .collection-card").forEach(patchCard)}
var timer=0;
function schedule(){clearTimeout(timer);timer=setTimeout(patchAll,0)}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",schedule,{once:true});else schedule();
new MutationObserver(schedule).observe(document.documentElement,{childList:true,subtree:true});
window.addEventListener("resize",schedule,{passive:true});
window.addEventListener("pageshow",schedule);
})();
