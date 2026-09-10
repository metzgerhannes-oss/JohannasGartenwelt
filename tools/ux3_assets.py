from pathlib import Path
import json, struct, zlib, math

root=Path('.')
manifest={
  "name":"Johanna´s Gartenwelt",
  "short_name":"Gartenwelt",
  "description":"Persönliche Gartenpflege mit Pflanzen, Wetter, Gartenplan und Pflegekalender.",
  "lang":"de",
  "start_url":"./",
  "scope":"./",
  "display":"standalone",
  "orientation":"any",
  "background_color":"#fbf6ef",
  "theme_color":"#567a57",
  "icons":[
    {"src":"./icon-192.png","sizes":"192x192","type":"image/png","purpose":"any maskable"},
    {"src":"./icon-512.png","sizes":"512x512","type":"image/png","purpose":"any maskable"}
  ]
}
(root/'manifest.webmanifest').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n",encoding='utf-8')

svg='''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
<rect width="512" height="512" rx="118" fill="#4f7252"/>
<circle cx="256" cy="256" r="166" fill="#fbf6ef"/>
<path d="M256 369c2-85 2-150 0-210" fill="none" stroke="#4f7252" stroke-width="22" stroke-linecap="round"/>
<path d="M249 248c-70 7-115-30-123-94 67-9 115 25 123 94Z" fill="#8faa7e"/>
<path d="M263 302c72 5 116-33 122-98-67-7-114 29-122 98Z" fill="#6d8768"/>
<path d="M247 204c44-8 72-36 76-82-48-1-78 29-76 82Z" fill="#d7a7ad"/>
</svg>'''
(root/'icon.svg').write_text(svg,encoding='utf-8')

FOREST=(79,114,82,255)
CREAM=(251,246,239,255)
SAGE=(143,170,126,255)
MOSS=(109,135,104,255)
ROSE=(215,167,173,255)

def blend(a,b,t):
    return tuple(round(a[i]*(1-t)+b[i]*t) for i in range(4))

def png(path,n):
    pix=[FOREST]*(n*n)
    cx=cy=n/2
    radius=n*.325
    stem_w=max(2,n*.035)
    def setp(x,y,c):
        if 0<=x<n and 0<=y<n: pix[y*n+x]=c
    for y in range(n):
        for x in range(n):
            # soft cream garden-circle
            d=math.hypot(x+.5-cx,y+.5-cy)
            if d<=radius: setp(x,y,CREAM)
    # stem
    for y in range(round(n*.31),round(n*.73)):
        for x in range(round(cx-stem_w/2),round(cx+stem_w/2)+1):
            setp(x,y,FOREST)
    # three simple elliptical leaves, rotated
    def ellipse(ecx,ecy,rx,ry,ang,col):
        ca,sa=math.cos(ang),math.sin(ang)
        xmin=max(0,int(ecx-rx-ry-2)); xmax=min(n,int(ecx+rx+ry+3))
        ymin=max(0,int(ecy-rx-ry-2)); ymax=min(n,int(ecy+rx+ry+3))
        for yy in range(ymin,ymax):
            for xx in range(xmin,xmax):
                dx=xx+.5-ecx; dy=yy+.5-ecy
                u=dx*ca+dy*sa; v=-dx*sa+dy*ca
                q=(u/rx)**2+(v/ry)**2
                if q<=1: setp(xx,yy,col)
    ellipse(n*.38,n*.43,n*.13,n*.065,-.58,SAGE)
    ellipse(n*.63,n*.54,n*.135,n*.067,.57,MOSS)
    ellipse(n*.54,n*.32,n*.095,n*.047,-.82,ROSE)
    raw=bytearray()
    for y in range(n):
        raw.append(0)
        for x in range(n): raw.extend(pix[y*n+x])
    def chunk(tag,data):
        return struct.pack('>I',len(data))+tag+data+struct.pack('>I',zlib.crc32(tag+data)&0xffffffff)
    out=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',n,n,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(bytes(raw),9))+chunk(b'IEND',b'')
    Path(path).write_bytes(out)

png(root/'apple-touch-icon.png',180)
png(root/'icon-192.png',192)
png(root/'icon-512.png',512)
print('PWA assets generated')
