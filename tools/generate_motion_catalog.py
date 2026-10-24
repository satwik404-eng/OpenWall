#!/usr/bin/env python3
"""One deterministic vector catalog for native SwiftUI and Windows Canvas renderers."""
import json,math,pathlib,sys
root=pathlib.Path(__file__).resolve().parents[1]
def stop(c,a=1,p=0): return dict(color=c,alpha=a,location=p)
def fill(stops=None,kind='linear',start=(0,0),end=(1,1)):
 return dict(kind=kind,stops=stops or [stop(0),stop(1,.5,.5),stop(0,1,1)],start=start,end=end)
def shape(points,**kw):
 s=dict(points=points,closed=True,stroke=0,pivot=[.5,.5],rotation=0,rotate=0,driftX=0,driftY=0,pulse=0,rate=1,phase=0,warpX=0,warpY=0,frequency=4,fill=fill([stop(2,.28),stop(1,.18,.55),stop(0,.7,1)]),pixelRadius=0)
 s.update(kw);return s
def ellipse(cx,cy,rx,ry,n=48): return [[cx+math.cos(i*math.tau/n)*rx,cy+math.sin(i*math.tau/n)*ry,0] for i in range(n)]
def line(points,**kw):
 kw.setdefault("stroke",.0015)
 return shape(points,closed=False,**kw)
def stars(count=65):
 return [shape([[(i*137+17)%997/997,(i*79+43)%631/631*.57,0]],pixelRadius=1.25 if i%4==0 else .65,fill=fill([stop(-1,.5 if i%3==0 else .22)],kind='solid')) for i in range(count)]
scenes={}
scenes['waves']=[shape([[-.1,1.2,0]]+[[i/72*1.2-.1,.27+n*.073,1] for i in range(73)]+[[1.1,1.2,0]],warpY=.15,frequency=3.8,phase=n*.36,fill=fill([stop(2,.30),stop(1,.13,.5),stop(0,.7,1)],start=(.3,.25),end=(.6,1))) for n in range(7)]+stars()
# Every motion is periodic in 2π so lock-screen exports loop seamlessly.
scenes['ribbons']=[shape([[-.25,.2+n*.12,1],[1.25,-.35+n*.12,1],[1.25,-.30+n*.12,1],[-.25,.25+n*.12,1]],warpY=.075,frequency=5,phase=n*.5,driftY=.04,fill=fill([stop(2,.7),stop(1,.23,.55),stop(0,.05,1)])) for n in range(12)]
scenes['orbit']=[shape(ellipse(.5,.5,.12+i*.045,.11+i*.027),stroke=.0015+(i%3)*.0005,rotation=-.6,pivot=[.5,.5],rotate=.35,phase=i*.35,pulse=.055,fill=fill([stop(2,.6),stop(1,.12,.5),stop(2,.4,1)])) for i in range(12)]+stars(28)
scenes['bloom']=[shape(ellipse(.18+(i%3)*.32,.22+(i//3)*.47,.30,.38),pivot=[.18+(i%3)*.32,.22+(i//3)*.47],driftX=.08,driftY=.07,pulse=.14,phase=i*1.1,fill=fill([stop(2,.46),stop(1,.12,.55),stop(0,0,1)],kind='radial',start=(.18+(i%3)*.32,.22+(i//3)*.47),end=(0,.47))) for i in range(6)]
scenes['contours']=[line([[j/64*1.3-.15,.08+i*.038+math.sin(j/64*8+i*.1)*.07,1] for j in range(65)],warpY=.08,frequency=6,phase=i*.12,stroke=.0012,fill=fill([stop(1,.28),stop(2,.65,.5),stop(1,.08,1)])) for i in range(25)]
scenes['prisms']=[shape([[.1+(i%4)*.27,.15+(i//4)*.34,0],[.38+(i%4)*.27,.08+(i//4)*.34,0],[.25+(i%4)*.27,.50+(i//4)*.34,0]],pivot=[.25+(i%4)*.27,.3+(i//4)*.34],rotation=(i%3)*.5,rotate=.22,driftX=.04,driftY=.04,phase=i*.7,fill=fill([stop(2,.42),stop(1,.16,.5),stop(0,.05,1)])) for i in range(12)]
scenes['rain']=[line([[i*.041-.2,-.25,0],[i*.041-.03,.35+(i%5)*.15,0]],driftY=.16,phase=i*.73,rate=1+i%2,stroke=.001+(i%3)*.0005,fill=fill([stop(0,0),stop(1,.18,.4),stop(2,.8,1)],start=(0,0),end=(0,1))) for i in range(35)]
scenes['dunes']=[shape([[-.1,1.15,0]]+[[j/72*1.2-.1,.36+i*.08+math.sin(j/72*3.4+i*.8)*.075,1] for j in range(73)]+[[1.1,1.15,0]],warpY=.025,frequency=4,phase=i*.6,fill=fill([stop(2,.35),stop(1,.38,.45),stop(0,.95,1)],start=(.3,.25+i*.06),end=(.6,1))) for i in range(8)]
points=[[.1+(i*137%821)/1000,.12+(i*211%739)/1000,0] for i in range(24)]
scenes['constellation']=[line([points[i],points[(i+5)%24]],phase=i*.31,pulse=.025,fill=fill([stop(2,.08),stop(1,.3,.5),stop(2,.08,1)]),stroke=.0008) for i in range(24)]+[shape(ellipse(p[0],p[1],.003+(i%3)*.001,.004+(i%3)*.001),pivot=p[:2],pulse=.35,phase=i*.31,fill=fill([stop(2,.95)],kind='solid')) for i,p in enumerate(points)]
scenes['tunnel']=[shape([[.5+math.cos(j*math.tau/6)*(.07+i*.035),.5+math.sin(j*math.tau/6)*(.07+i*.035),0] for j in range(6)],stroke=.0016,pivot=[.5,.5],rotation=i*.07,rotate=.23,pulse=.08,phase=i*.14,fill=fill([stop(2,.6),stop(1,.1,.5),stop(2,.45,1)])) for i in range(18)]
scenes['petals']=[shape(ellipse(.5,.29,.065,.25),pivot=[.5,.5],rotation=i*math.tau/12,rotate=.15,pulse=.10,phase=i*.2,fill=fill([stop(2,.16),stop(1,.35,.5),stop(2,.08,1)],start=(.5,.1),end=(.5,.9))) for i in range(12)]
original=[('aurora','Northern lights',[[.015,.07,.085],[.05,.52,.39],[.50,.91,.60]]),('dusk','Afterglow',[[.10,.025,.14],[.97,.33,.20],[1,.70,.37]]),('ocean','Deep current',[[.012,.04,.15],[.06,.30,.74],[.22,.83,.92]]),('ember','Ember glow',[[.12,.015,.02],[.84,.13,.045],[1,.58,.16]]),('amethyst','Amethyst drift',[[.055,.015,.14],[.42,.16,.77],[.81,.56,1]]),('glacier','Glacier light',[[.02,.10,.17],[.19,.56,.68],[.79,.96,.98]]),('solar','Solar tide',[[.17,.05,.02],[.88,.40,.08],[1,.86,.36]]),('midnight','Midnight silk',[[.025,.03,.055],[.18,.22,.34],[.57,.66,.83]]),('rose','Rosewater',[[.12,.025,.09],[.69,.25,.45],[1,.68,.75]])]
palettes=[('jade','Jade',[[.012,.045,.035],[.035,.42,.27],[.58,1,.70]]),('arctic','Arctic',[[.01,.03,.075],[.055,.38,.70],[.56,.94,1]]),('violet','Violet',[[.035,.012,.065],[.37,.12,.67],[.88,.62,1]]),('coral','Coral',[[.06,.012,.03],[.72,.17,.30],[1,.71,.53]]),('gold','Gold',[[.055,.025,.008],[.65,.35,.045],[1,.88,.47]])]
palettes += [('midnight','Midnight Silk',[[.025,.03,.055],[.18,.22,.34],[.57,.66,.83]]),('lightblue','Light Blue',[[.035,.085,.15],[.24,.58,.82],[.77,.93,1]]),('teal','Teal Green',[[.008,.055,.055],[.025,.43,.43],[.39,.91,.78]])]
styles=[('ribbons','Silk ribbons'),('orbit','Orbital rings'),('bloom','Luminous bloom'),('contours','Contour flow'),('prisms','Prism drift'),('rain','Neon rain'),('dunes','Dune horizon'),('constellation','Constellation'),('tunnel','Vortex tunnel'),('petals','Petal dance')]
items=[dict(id=i,name=n,style='waves',palette=c) for i,n,c in original]+[dict(id=s+'-'+p,name=n+' · '+pn,style=s,palette=c) for s,n in styles for p,pn,c in palettes]
# Round geometry only; palettes retain the original native SwiftUI values.
for scene in scenes.values():
 for s in scene: s['points']=[[round(v,7) for v in p] for p in s['points']]
catalog=dict(version=1,items=items,scenes=scenes,background=fill())
data=json.dumps(catalog,separators=(',',':'),ensure_ascii=False)+'\n'
outputs={'Shared/motion-catalog.json':data,'Shared/motion-catalog.js':"'use strict';\nwindow.OpenWallCatalog="+data.rstrip()+';\n'}
for name,value in outputs.items():
 p=root/name
 if '--check' in sys.argv: assert p.read_text()==value, name+' is stale; run tools/generate_motion_catalog.py'
 else: p.write_text(value)
print('PASS shared catalog: 9 original + 10 styles × 8 palettes = 89 wallpapers; '+str(sum(map(len,scenes.values())))+' vector shapes')
