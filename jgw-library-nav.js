(function(){
"use strict";
/* Stable entrypoint referenced by index.html. The split files load synchronously before the next app script. */
if(window.__jgwUxBundleLoader)return;window.__jgwUxBundleLoader=true;
var base=(document.currentScript&&document.currentScript.src)||location.href;
var root=base.slice(0,base.lastIndexOf("/")+1);
function tag(file,version){return '<script src="'+root+file+'?v='+version+'"></'+'script>'}
document.write(tag("jgw-ux-shell.js","20260914-3")+tag("jgw-library-v4.js","20260914-2")+tag("jgw-ux-patch.js","20260914-1")+tag("jgw-photo-storage-v2.js","20260914-2")+tag("jgw-ui-cleanup-20260914.js","20260914-3")+tag("jgw-mobile-fix-v5.js","20260914-1")+tag("jgw-hardiness-data-v1.js","20260917-1")+tag("jgw-hardiness-v2.js","20260917-1")+tag("jgw-hardiness-labels-v1.js","20260917-1"));
})();
