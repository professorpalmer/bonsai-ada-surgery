"""P188: compare the null arm and the window arms with the window-off receipts (#174). Run from anywhere."""
import json,os,re
d=os.path.dirname(os.path.abspath(__file__))
def L(n):
    f=os.path.join(d,n+'.jsonl')
    if not os.path.exists(f): f=os.path.join(os.path.dirname(d),n+'.jsonl')  # the #174 receipts
    return {r['item']:r for r in map(json.loads,open(f,encoding='utf-8'))}
def cls(r):
    if r['ok']: return 'ok'
    return 'miss' if re.search(r"does not|not (stated|mentioned|specified|given)|no (mention|information)|cannot",r['answer'],re.I) else 'wrong'
tot={}
for s in ['code','prose']:
    off=L('t5rel_r2b_off_'+s); arms={'null':L('p188_'+s),'win':L('t5rel_r2b_on_'+s),'d8':L('t5_d8_'+s)}
    for an,a in arms.items():
        ch=[i for i in off if a[i]['answer']!=off[i]['answer']]
        flip=[i for i in off if a[i]['ok']!=off[i]['ok']]
        cw=[i for i in off if off[i]['ok'] and cls(a[i])=='wrong']
        gain=[i for i in off if not off[i]['ok'] and a[i]['ok']]
        c={k:sum(cls(a[i])==k for i in a) for k in ['ok','miss','wrong']}
        print(s,an,'text changed',len(ch),'ok-flips',flip,'conf-wrong(off right)',cw,'gained',gain,c)
        t=tot.setdefault(an,[0,0,0,0]); t[0]+=len(cw); t[1]+=len(gain); t[2]+=c['wrong']; t[3]+=c['ok']
    c={k:sum(cls(off[i])==k for i in off) for k in ['ok','miss','wrong']}; print(s,'off',c)
print('totals [conf-wrong-vs-off, gained, wrong, ok]',tot)
for s in ['code','prose']:
    off=L('t5rel_r2b_off_'+s); nu=L('p188_'+s)
    for i in off:
        if off[i]['ok']!=nu[i]['ok']: print(s,i,'off',repr(off[i]['answer'][:60]),'| null',repr(nu[i]['answer'][:60]))
