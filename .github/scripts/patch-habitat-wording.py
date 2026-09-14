from pathlib import Path
p=Path('index.html')
s=p.read_text(encoding='utf-8')
old='Konkrete Lebensräume werden jetzt in der Naturgarten-Sammlung als Foto-Karten gepflegt. Hier stehen nur übergreifende Gartenprinzipien.'
new='Konkrete Lebensräume werden in der Naturgarten-Sammlung als einheitliche Karten gepflegt. Eigene Fotos bleiben in der Detailansicht erhalten. Hier stehen nur übergreifende Gartenprinzipien.'
if old in s:
    s=s.replace(old,new,1)
elif new not in s:
    raise SystemExit('Hinweistext nicht gefunden')
p.write_text(s,encoding='utf-8')
