(function(){
"use strict";
/* Synchronous UX bundle loader. This file stays as the stable entrypoint referenced by index.html. */
if(window.__jgwUxBundleLoader)return;window.__jgwUxBundleLoader=true;
var base=(document.currentScript&&document.currentScript.src)||location.href;
var root=base.slice(0,base.lastIndexOf("/")+1);
function tag(file,version){return '<script src="'+root+file+'?v='+version+'"><\\/script>'}
document.write(tag("jgw-ux-shell.js","20260913-1")+tag("jgw-library-v4.js","20260913-1"));
})();