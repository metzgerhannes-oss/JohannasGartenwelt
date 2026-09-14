(function(){
"use strict";
if(window.__jgwUiCleanup20260914)return;window.__jgwUiCleanup20260914=true;
var css=document.createElement("style");
css.id="jgwUiCleanup20260914";
css.textContent=`
/* Kompakter Regenhinweis */
.jgw-yesterday-rain{
  margin-top:8px!important;
  padding:9px 11px!important;
  display:grid!important;
  grid-template-columns:minmax(0,1fr) auto!important;
  align-items:center!important;
  gap:8px!important;
  border-radius:14px!important;
  box-shadow:none!important;
}
.jgw-yesterday-rain b{font-size:15px!important;line-height:1.2!important}
.jgw-yesterday-rain .muted{font-size:11px!important;line-height:1.25!important;margin-top:2px!important}
.jgw-yesterday-rain .muted[style*="font-size:11px"]{display:none!important}
.jgw-yesterday-rain .jgw-rain-correct-btn{min-height:34px!important;height:34px!important;padding:5px 9px!important;font-size:10.5px!important;white-space:nowrap!important}

/* Dezenter schwebender Hinzufügen-Button */
.jgw-fab{
  width:48px!important;
  height:48px!important;
  right:13px!important;
  bottom:calc(82px + env(safe-area-inset-bottom) + var(--jgw-browser-bottom,0px))!important;
  box-shadow:0 7px 18px rgba(63,104,68,.22)!important;
}
.jgw-fab svg{width:23px!important;height:23px!important}

/* Pflanzenübersicht: Name hat Vorrang */
@media(max-width:700px){
  #plantCollectionWrap.collection-grid,
  #plantCollectionWrap .collection-grid{grid-template-columns:repeat(2,minmax(0,1fr))!important;gap:9px!important}
  #plantCollectionWrap .collection-card{
    display:block!important;
    grid-template-columns:none!important;
    grid-template-rows:none!important;
    flex-direction:column!important;
    flex-wrap:nowrap!important;
    align-items:stretch!important;
    min-width:0!important;
    min-height:0!important;
    overflow:hidden!important;
  }
  #plantCollectionWrap .collection-photo{
    display:grid!important;
    width:100%!important;
    height:auto!important;
    aspect-ratio:16/10!important;
    grid-column:auto!important;
    grid-row:auto!important;
    border-radius:0!important;
    position:relative!important;
    overflow:hidden!important;
  }
  #plantCollectionWrap .collection-photo>.collection-card-main{
    display:block!important;
    width:100%!important;
    height:100%!important;
  }
  #plantCollectionWrap .collection-photo img{
    width:100%!important;
    height:100%!important;
    object-fit:cover!important;
  }
  #plantCollectionWrap .collection-card>button.collection-card-main{
    display:block!important;
    width:100%!important;
    min-width:0!important;
    grid-column:auto!important;
    grid-row:auto!important;
  }
  #plantCollectionWrap .collection-body{
    display:block!important;
    width:100%!important;
    min-width:0!important;
    padding:8px 9px 10px!important;
  }
  #plantCollectionWrap .collection-name{
    display:-webkit-box!important;
    -webkit-box-orient:vertical!important;
    -webkit-line-clamp:2!important;
    overflow:hidden!important;
    white-space:normal!important;
    text-overflow:clip!important;
    overflow-wrap:anywhere!important;
    font-size:14px!important;
    line-height:1.15!important;
    min-height:2.3em!important;
    color:var(--forest-dark)!important;
    font-weight:800!important;
    padding:0!important;
    margin:0!important;
  }
  #plantCollectionWrap .collection-latin{
    display:block!important;
    margin-top:3px!important;
    font-size:9.5px!important;
    line-height:1.2!important;
    white-space:nowrap!important;
    overflow:hidden!important;
    text-overflow:ellipsis!important;
  }
  #plantCollectionWrap .collection-area{
    display:block!important;
    margin-top:3px!important;
    font-size:10px!important;
    line-height:1.2!important;
    white-space:nowrap!important;
    overflow:hidden!important;
    text-overflow:ellipsis!important;
  }
  #plantCollectionWrap .collection-status{
    display:block!important;
    margin-top:4px!important;
    font-size:10px!important;
    line-height:1.2!important;
    white-space:nowrap!important;
    overflow:hidden!important;
    text-overflow:ellipsis!important;
  }
  #plantCollectionWrap .collection-chips{display:none!important}
  #plantCollectionWrap .collection-card-name-mobile{display:none!important}

  /* Aktionen liegen kompakt auf dem Foto statt neben dem Namen */
  #plantCollectionWrap .insect-badge{
    display:flex!important;
    align-items:center!important;
    position:absolute!important;
    left:6px!important;
    top:6px!important;
    right:auto!important;
    bottom:auto!important;
    min-height:25px!important;
    padding:3px 7px!important;
    border-radius:999px!important;
    font-size:10.5px!important;
    line-height:1!important;
    z-index:6!important;
    background:rgba(255,253,249,.92)!important;
    color:var(--forest-dark)!important;
    border:1px solid rgba(255,255,255,.82)!important;
    box-shadow:0 2px 7px rgba(54,49,44,.12)!important;
    backdrop-filter:blur(4px)!important;
  }
  #plantCollectionWrap .favorite-plant{
    display:grid!important;
    place-items:center!important;
    position:absolute!important;
    right:6px!important;
    top:6px!important;
    left:auto!important;
    bottom:auto!important;
    width:30px!important;
    height:30px!important;
    min-width:30px!important;
    min-height:30px!important;
    font-size:18px!important;
    z-index:7!important;
  }
  #plantCollectionWrap .plant-add-one{
    display:grid!important;
    place-items:center!important;
    position:absolute!important;
    right:6px!important;
    bottom:6px!important;
    top:auto!important;
    left:auto!important;
    width:32px!important;
    min-width:32px!important;
    height:28px!important;
    min-height:28px!important;
    padding:0!important;
    border-radius:999px!important;
    font-size:11px!important;
    z-index:7!important;
  }
  #plantCollectionWrap .plant-quantity-badge{
    left:6px!important;
    bottom:6px!important;
    right:auto!important;
    top:auto!important;
    min-width:25px!important;
    height:25px!important;
    font-size:10px!important;
    z-index:7!important;
  }
}
`;
document.head.appendChild(css);
})();
