'use strict';

(async function bootstrap(){
  state = await loadState();
  if('serviceWorker' in navigator){
    navigator.serviceWorker.register('./sw.js?v=0.9.15')
      .then(reg=>reg.update().catch(()=>{}))
      .catch(console.warn);
  }
  bind();
  renderAll();
})();