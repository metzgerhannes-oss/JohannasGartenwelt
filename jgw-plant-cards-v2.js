(function(){
"use strict";
if(window.__jgwPlantCardsV2)return;window.__jgwPlantCardsV2=true;
var css=document.createElement("style");
css.id="jgwPlantCardsV2Style";
css.textContent=`
.collection-card-name-mobile{display:none!important}
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
  #plantList.collection-grid:not(.list-mode) .collection-photo>.collection-card-main,
  #plantHighlights .collection-photo>.collection-card-main,
  #plantFavorites .collection-photo>.collection-card-main{
    display:block!important;
    width:100%!important;
    height:100%!important;
    min-width:0!important;
  }
  #plantList.collection-grid:not(.list-mode) .collection-photo img,
  #plantHighlights .collection-photo img,
  #plantFavorites .collection-photo img{
    display:block!important;
    width:100%!important;
    height:100%!important;
    object-fit:cover!important;
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
    min-height:2.4em!important;
    max-height:2.4em!important;
    font-size:15px!important;
    line-height:1.2!important;
    padding:0!important;
    margin:0!important;
    color:var(--forest-dark)!important;
  }
  #plantList.collection-grid:not(.list-mode) .collection-latin,
  #plantHighlights .collection-latin,
  #plantFavorites .collection-latin{
    margin-top:4px!important;
    min-height:0!important;
    font-size:9px!important;
    white-space:nowrap!important;
    overflow:hidden!important;
    text-overflow:ellipsis!important;
  }
  #plantList.collection-grid:not(.list-mode) .collection-area,
  #plantHighlights .collection-area,
  #plantFavorites .collection-area{
    margin-top:4px!important;
    font-size:10px!important;
    white-space:nowrap!important;
    overflow:hidden!important;
    text-overflow:ellipsis!important;
  }
  #plantList.collection-grid:not(.list-mode) .collection-status,
  #plantHighlights .collection-status,
  #plantFavorites .collection-status{
    margin-top:6px!important;
    font-size:10px!important;
  }
  #plantList.collection-grid:not(.list-mode) .insect-badge,
  #plantHighlights .insect-badge,
  #plantFavorites .insect-badge{
    display:block!important;
    right:7px!important;
    top:7px!important;
    padding:4px 7px!important;
    font-size:10px!important;
  }
  #plantList.collection-grid:not(.list-mode) .favorite-plant,
  #plantHighlights .favorite-plant,
  #plantFavorites .favorite-plant{
    left:7px!important;
    top:7px!important;
    width:34px!important;
    height:34px!important;
  }
  #plantList.collection-grid:not(.list-mode) .plant-add-one,
  #plantHighlights .plant-add-one,
  #plantFavorites .plant-add-one{
    display:grid!important;
    right:7px!important;
    bottom:7px!important;
    top:auto!important;
    min-width:38px!important;
    height:30px!important;
    padding:0 9px!important;
  }
  #plantList.collection-grid:not(.list-mode) .plant-quantity-badge,
  #plantHighlights .plant-quantity-badge,
  #plantFavorites .plant-quantity-badge{
    left:7px!important;
    right:auto!important;
    bottom:7px!important;
  }
}
`;
document.head.appendChild(css);
})();
