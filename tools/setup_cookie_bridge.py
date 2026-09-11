from pathlib import Path
p=Path('setup.html')
s=p.read_text(encoding='utf-8')

if '<link rel="manifest" href="./setup.webmanifest">' not in s:
    s=s.replace('<link rel="apple-touch-icon" href="./app-icon-180.png">','<link rel="apple-touch-icon" href="./app-icon-180.png">\n<link rel="manifest" href="./setup.webmanifest">',1)

s=s.replace('var receiverContext="standalone";','var receiverContext="standalone";\nvar SETUP_COOKIE="jgw_setup_install";',1)

anchor='function readJSON(key){try{return JSON.parse(localStorage.getItem(key)||"null")||{}}catch(e){return{}}}'
insert='''function readJSON(key){try{return JSON.parse(localStorage.getItem(key)||"null")||{}}catch(e){return{}}}\nfunction setupCookiePath(){var p=location.pathname||"/";return p.slice(0,p.lastIndexOf("/")+1)||"/"}\nfunction setInstallCookie(token){if(!token)return;document.cookie=SETUP_COOKIE+"="+encodeURIComponent(token)+"; Max-Age=3600; Path="+setupCookiePath()+"; Secure; SameSite=Strict"}\nfunction getInstallCookie(){var parts=(document.cookie||"").split(";");for(var i=0;i<parts.length;i++){var x=parts[i].trim(),prefix=SETUP_COOKIE+"=";if(x.indexOf(prefix)===0){try{return decodeURIComponent(x.slice(prefix.length))}catch(e){return x.slice(prefix.length)}}}return""}\nfunction clearInstallCookie(){document.cookie=SETUP_COOKIE+"=; Max-Age=0; Path="+setupCookiePath()+"; Secure; SameSite=Strict"}\nfunction hasValidStoredConfig(){var c=currentConfig();return validUrl(c.url)&&c.key.length>10&&c.gardenId.length>=6&&c.pin.length>=6}'''
if anchor not in s:
    raise SystemExit('readJSON anchor missing')
s=s.replace(anchor,insert,1)

old='function showInstallGuide(token){activeToken=token;putTokenInInstallUrl(token);hideAll();show("installBox",true)}'
new='function showInstallGuide(token){activeToken=token;setInstallCookie(token);putTokenInInstallUrl(token);hideAll();show("installBox",true)}'
if old not in s:
    raise SystemExit('showInstallGuide anchor missing')
s=s.replace(old,new,1)

old2='storeConfig(p,pin);clearSetupUrl();el("receiverStatus").className="status ok";'
new2='storeConfig(p,pin);clearInstallCookie();clearSetupUrl();el("receiverStatus").className="status ok";'
if old2 not in s:
    raise SystemExit('unlock anchor missing')
s=s.replace(old2,new2,1)

# Replace init with cookie-aware standalone flow
start=s.find('function init(){')
end=s.find('\ninit();',start)
if start<0 or end<0:
    raise SystemExit('init block missing')
old_init=s[start:end]
new_init='''function init(){var installToken=tokenFromInstallQuery(),hashToken=tokenFromHash(),standalone=isStandalone(),cookieToken=getInstallCookie();hideAll();\nif(standalone){\n  if(installToken&&installToken!=="1")showReceiver(installToken,"standalone");\n  else if(hashToken)showReceiver(hashToken,"standalone");\n  else if(cookieToken)showReceiver(cookieToken,"standalone");\n  else if(hasValidStoredConfig()){location.replace("./");return}\n  else{show("receiverBox",true);el("standaloneConfirmed").className="status warn";el("standaloneConfirmed").innerHTML="<b>Web-App-Modus erkannt.</b><br>Die Einrichtungsdaten wurden aber nicht übernommen.";el("receiverIntro").innerHTML="Bitte dieses Symbol wieder entfernen und die Einrichtung erneut über den QR-Code starten. Beim Hinzufügen muss <b>Als Web-App öffnen</b> aktiv sein.";el("unlockForm").classList.add("hidden");el("receiverStatus").className="status bad";el("receiverStatus").textContent="Einrichtungsdaten fehlen."}\n}else if(installToken&&installToken!=="1")showInstallGuide(installToken);\nelse if(hashToken)showInstallGuide(hashToken);\nelse{show("generatorBox",true);renderChecks()}\nel("makeQr").addEventListener("click",makeQr);el("copyLink").addEventListener("click",copyLink);el("unlockForm").addEventListener("submit",unlockSetup);el("cancelSetup").addEventListener("click",cancelSetup);el("cancelInstall").addEventListener("click",cancelInstall);el("safariOnly").addEventListener("click",safariOnly)}'''
s=s[:start]+new_init+s[end:]

# Clarify copy bridge to user
s=s.replace('Safari und eine zum Home-Bildschirm hinzugefügte Web-App verwenden auf iPhone/iPad getrennte lokale Speicherbereiche. Deshalb muss die Einrichtung innerhalb der Home-Screen-App abgeschlossen werden.','Safari und die Home-Screen-Web-App haben getrennte lokale Speicher. Die verschlüsselten Einrichtungsdaten werden deshalb für kurze Zeit über einen sicheren Installations-Cookie an die neue Web-App übergeben; die PIN bleibt separat.',1)

p.write_text(s,encoding='utf-8')
print('patched',len(s))
