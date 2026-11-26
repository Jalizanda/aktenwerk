"""Führt das Aktenwerk-Gerichtsverzeichnis mit den Gerichts-Stammdaten des
GutachtenManagers zusammen (einmalig für v0.21.0 verwendet).

Aufruf:  python3 tool/gerichte_zusammenfuehren.py ALT.json GM_gerichte.json ZIEL.json
  ALT.json        bisheriges assets/data/gerichte.json (z. B. aus git show)
  GM_gerichte.json  aus GutachtenBuero/stammdaten/gerichte.json
GM-Anschriften/Telefon/Fax haben Vorrang (aktueller), Name und Typ bleiben.
"""
import json,re,collections,sys
alt=json.load(open(sys.argv[1]))
gm=json.load(open(sys.argv[2]))
TYP=[('Oberstaatsanwaltschaft','OStA'),('Staatsanwaltschaft','StA'),('Generalprokuratur','GP'),('Arbeits- und Sozialgericht','ASG'),
 ('Amtsgericht','AG'),('Landgericht','LG'),('Oberlandesgericht','OLG'),('Bezirksgericht','BG'),('Landesgericht','LG'),('Handelsgericht','HG')]
def typ(n):
    for p,t in TYP:
        if n.startswith(p): return t
    return ''
def name(x):
    n=x['name'].strip(); z=x['zusatz'].strip()
    if n=='Landgericht Berlin':
        if z.startswith('(Zivil'): return 'Landgericht Berlin II'+(' – Standort Littenstraße' if '2.' in z else '')
        return 'Landgericht Berlin I'
    if not z: return n
    if z.startswith('('): return f'{n} {z}'
    if n=='Amtsgericht Hamburg' and not z.startswith('Zweig'): return f'Amtsgericht Hamburg-{z}'
    return f'{n} – {z}'
def tel(s):
    s=(s or '').strip()
    return re.sub(r'\s*/\s*',' ',s) if not s.startswith('+') else s
norm=lambda s: re.sub(r'\s+',' ',s.lower().replace('–','-')).strip()
def strk(s):
    s=s.lower().replace('ß','ss'); s=re.sub(r'str(asse|\.)','str',s); return re.sub(r'[^a-z0-9]','',s)
out=[dict(g) for g in alt if g['name']!='Landgericht Berlin']
idx={norm(g['name']):g for g in out}
idx2={(g['typ'],g['plz'],strk(g['strasse'])):g for g in out}
stat=collections.Counter()
for x in gm:
    n=name(x)
    rec={'typ':typ(n),'name':n,'strasse':x['strasse'].strip(),'plz':x['plz'].strip(),'ort':x['stadt'].strip(),
         'telefon':tel(x['telefon']),'fax':tel(x['fax']),'land':x['land'] or 'DE'}
    if n=='Landgericht Berlin I': rec.update(strasse='Turmstraße 91',plz='10559')
    if n=='Landgericht Halle': rec.update(strasse='Hansering 13',plz='06108',ort='Halle (Saale)')
    if x['postfach'].strip(): rec['postfach']=x['postfach'].strip()
    if rec['strasse'].lower().startswith('postfach'):
        rec['postfach']=rec['strasse']; rec['strasse']=''
    k=norm(n); k2=norm(re.sub(r'\s*\([^)]*\)$','',n))
    g=idx.get(k) or idx.get(k2) or (None if x['zusatz'].strip() else idx2.get((rec['typ'],rec['plz'],strk(rec['strasse']))))
    if g:
        # GM-Daten sind aktueller: Anschrift/Telefon/Fax übernehmen, Name & Typ behalten
        felder=('strasse','plz','ort','telefon','fax','postfach') if rec['strasse'] else ('telefon','fax','postfach')
        for f in felder:
            if rec.get(f): g[f]=rec[f]
        stat['aktualisiert']+=1
    else:
        out.append(rec); idx[k]=rec; idx2[(rec['typ'],rec['plz'],strk(rec['strasse']))]=rec; stat['neu']+=1
for g in out: g.setdefault('land','DE')
for g in out:
    m=re.search(r'\(([^)]+)\)$',g['ort'])
    if m and '(' not in g['name'] and '–' not in g['name']:
        stadt=g['ort'][:m.start()].strip()
        if g['name'].endswith(' '+stadt): g['name']+=f' ({m.group(1)})'
rang={'DE':0,'AT':1}
out.sort(key=lambda g:(rang.get(g['land'],2), 0 if g['typ'] in ('BGH','BVerfG','BVerwG','BFH','BSG','BAG','BPatG') else 1, g['name']))
json.dump(out,open(sys.argv[3],'w'),ensure_ascii=False,indent=1)
c=collections.Counter(g['name'] for g in out)
print(dict(stat),'gesamt',len(out),'doppelt',[n for n,v in c.items() if v>1])
print([g for g in out if g['name'].startswith(('Landgericht Berlin','Amtsgericht Menden','Landgericht Mönchengladbach','Amtsgericht Wesel'))])
print(collections.Counter(g['land'] for g in out), sum(1 for g in out if not g.get('strasse')),'ohne Straße')
