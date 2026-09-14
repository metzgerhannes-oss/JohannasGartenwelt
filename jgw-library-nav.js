(function(){
"use strict";
/* Stable entrypoint referenced by index.html. The split files load synchronously before the next app script. */
if(window.__jgwUxBundleLoader)return;window.__jgwUxBundleLoader=true;
var base=(document.currentScript&&document.currentScript.src)||location.href;
var root=base.slice(0,base.lastIndexOf("/")+1);
function tag(file,version){return '<script src="'+root+file+'?v='+version+'"></'+'script>'}
var buildStyle='<style id="jgwGalleryVersionStatic">#plantCollectionWrap::before{content:"Galerie-Version: 2026.09.14-03";display:block;grid-column:1/-1;margin:0 0 10px;padding:6px 10px;border:1px solid #d9ccb8;border-radius:999px;background:#fffaf1;color:#7a6f62;font:700 11px/1.2 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;text-align:center;letter-spacing:.02em}</style>';
document.write(buildStyle+tag("jgw-ux-shell.js","20260914-2")+tag("jgw-library-v4.js","20260914-2")+tag("jgw-ux-patch.js","20260914-1")+tag("jgw-photo-storage-v2.js","20260914-2"));
})();
