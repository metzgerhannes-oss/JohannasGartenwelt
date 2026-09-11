from pathlib import Path

p=Path('setup.html')
s=p.read_text(encoding='utf-8')

old='''<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">\n<meta name="theme-color" content="#8faa7e">'''
new='''<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">\n<meta name="mobile-web-app-capable" content="yes">\n<meta name="apple-mobile-web-app-capable" content="yes">\n<meta name="apple-mobile-web-app-status-bar-style" content="default">\n<meta name="apple-mobile-web-app-title" content="Johanna´s Gartenwelt">\n<meta name="theme-color" content="#8faa7e">'''
if old not in s:
    raise SystemExit('setup head anchor missing')
s=s.replace(old,new,1)

s=s.replace(
'''<div class="installhero"><b>Wichtig:</b> Die PIN jetzt noch nicht eingeben. Zuerst die Seite als Web-App zum Home-Bildschirm hinzufügen. So werden die Zugangsdaten direkt im Speicher der Home-Screen-App eingerichtet.</div>''',
'''<div class="installhero"><b>Wichtig:</b> Die PIN jetzt noch nicht eingeben. Zuerst diese Seite zum Home-Bildschirm hinzufügen und <b>„Als Web-App öffnen“ eingeschaltet lassen</b>. Danach ausschließlich das neue Gartenwelt-Symbol auf dem Home-Bildschirm öffnen. <b>Wenn oben noch eine Internetadresse oder unten Safari-Schaltflächen sichtbar sind, bist du noch im Browser und nicht in der Web-App.</b></div>''',1)

s=s.replace(
'''<div class="actions"><button class="btn secondary" id="safariOnly" type="button">Nur in Safari einrichten</button><button class="btn ghost" id="cancelInstall" type="button">Abbrechen</button></div>''',
'''<div class="actions"><button class="btn secondary hidden" id="safariOnly" type="button" aria-hidden="true" tabindex="-1">Nur in Safari einrichten</button><button class="btn ghost" id="cancelInstall" type="button">Abbrechen</button></div>''',1)

# Add a clear mode diagnostic so a user immediately sees whether the Home Screen icon
# really launched standalone mode.
needle='''  <section class="box hidden" id="receiverBox">\n    <span class="modepill" id="receiverMode">Home-Screen-App</span>'''
repl='''  <section class="box hidden" id="receiverBox">\n    <span class="modepill" id="receiverMode">Home-Screen-App</span>\n    <div class="status ok" id="standaloneConfirmed"><b>Web-App-Modus erkannt.</b><br>Keine Safari-Leisten sollten sichtbar sein.</div>'''
if needle not in s:
    raise SystemExit('receiver anchor missing')
s=s.replace(needle,repl,1)

# If someone somehow invokes the receiver in Safari, make the warning impossible to miss.
old2='''function showReceiver(token,context){activeToken=token;receiverContext=context||"standalone";hideAll();show("receiverBox",true);el("receiverMode").textContent=receiverContext==="safari"?"Safari":"Home-Screen-App";el("receiverIntro").innerHTML=receiverContext==="safari"?"Du richtest nur Safari ein. <b>Wenn du die Seite später als Web-App zum Home-Bildschirm hinzufügst, muss die Home-Screen-App separat eingerichtet werden.</b>":"Der Einrichtungs-Code wurde in die Home-Screen-App übernommen. Gib jetzt nur noch die Garten-PIN ein.";setTimeout(function(){try{el("setupPin").focus()}catch(e){}},80)}'''
new2='''function showReceiver(token,context){activeToken=token;receiverContext=context||"standalone";hideAll();show("receiverBox",true);el("receiverMode").textContent=receiverContext==="safari"?"Safari":"Home-Screen-App";show("standaloneConfirmed",receiverContext!=="safari");el("receiverIntro").innerHTML=receiverContext==="safari"?"Du bist noch in Safari. Bitte nicht hier einrichten, sondern zuerst als Web-App zum Home-Bildschirm hinzufügen und anschließend das neue Home-Screen-Symbol öffnen.":"Der Einrichtungs-Code wurde in die Home-Screen-App übernommen. Gib jetzt nur noch die Garten-PIN ein.";setTimeout(function(){try{el("setupPin").focus()}catch(e){}},80)}'''
if old2 not in s:
    raise SystemExit('showReceiver anchor missing')
s=s.replace(old2,new2,1)

p.write_text(s,encoding='utf-8')
print('patched setup.html',len(s))
