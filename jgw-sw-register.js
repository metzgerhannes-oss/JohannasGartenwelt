(function(){
  if(!("serviceWorker" in navigator)||location.protocol!=="https:")return;
  window.addEventListener("load",function(){navigator.serviceWorker.register("./sw.js",{scope:"./"}).catch(function(e){console.warn("Service Worker",e)})},{once:true});
  window.addEventListener("offline",function(){try{window.JGWCore&&JGWCore.notice&&JGWCore.notice("Offline-Modus: Garten und gespeicherte Daten bleiben verfügbar.")}catch(e){}});
  window.addEventListener("online",function(){try{window.JGWCore&&JGWCore.notice&&JGWCore.notice("Wieder online.")}catch(e){}try{window.JGWCore&&JGWCore.syncCheckRemote&&JGWCore.syncCheckRemote()}catch(e){}try{var s=window.JGWCore&&JGWCore.getState?JGWCore.getState():null;if(s&&(s.plz||s.gardenCenter)&&JGWCore.refreshWeather)JGWCore.refreshWeather(false)}catch(e){}});
})();
