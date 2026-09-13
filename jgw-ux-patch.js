(function(){
"use strict";
if(window.__jgwUxPatchV4)return;window.__jgwUxPatchV4=true;
function el(id){return document.getElementById(id)}
function q(s,r){return(r||document).querySelector(s)}
function qa(s,r){return Array.from((r||document).querySelectorAll(s))}
function stabilizeHabitats(){var old=el("habitatList");if(!old||old.dataset.jgwStablePlanning==="1")return;var fresh=old.cloneNode(false);fresh.dataset.jgwStablePlanning="1";old.replaceWith(fresh);function organize(){var list=el("habitatList");if(!list||q(".jgw-habitat-planning-title",list))return;var cards=qa(":scope > .nature-card",list),planned=cards.filter(function(c){return!!q(".nature-chip.plan",c)});if(!planned.length||planned.length===cards.length)return;var title=document.createElement("div");title.className="jgw-habitat-planning-title";title.textContent="Ideen & Planung";list.appendChild(title);planned.forEach(function(c){list.appendChild(c)})}var list=el("habitatList");new MutationObserver(function(){setTimeout(organize,0)}).observe(list,{childList:true,subtree:true});try{if(window.JGWCore&&JGWCore.renderHabitats)JGWCore.renderHabitats();else if(window.renderHabitats)window.renderHabitats()}catch(e){}organize()}
function repairPhotos(){["plantPhoto","habitatPhoto","animalPhoto"].forEach(function(id){var i=el(id);if(i&&!i.matches(":focus"))i.removeAttribute("capture")})}
function repairLabels(){[["plantEditorTitle","plantForm","saveAndPlaceBtn"],["habitatEditorTitle","habitatForm","saveHabitatAndPlaceBtn"],["animalEditorTitle","animalForm","saveAnimalAndPlaceBtn"]].forEach(function(x){var title=el(x[0]),form=el(x[1]),place=el(x[2]),submit=form&&q('button[type="submit"]',form);if(place){place.textContent="Speichern & auf Karte setzen";place.classList.remove("secondary")}if(submit){submit.textContent=title&&/bearbeiten/i.test(title.textContent)?"Änderungen speichern":"Nur speichern";submit.classList.add("secondary")}})}
function removeOldAdvisor(){var b=el("moreAdvisorBtn");if(b)b.remove()}
function repair(){repairPhotos();repairLabels();removeOldAdvisor()}
stabilizeHabitats();if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",function(){setTimeout(repair,0)},{once:true});else setTimeout(repair,0);window.addEventListener("pageshow",repair);
})();