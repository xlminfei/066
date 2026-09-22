#!/usr/bin/env python3
"""Independent 100-decimal incomplete-Beta reference; no research data or fits."""
import csv, hashlib, json, pathlib, sys, time
root = pathlib.Path(__file__).resolve().parents[1]
wheel = root / 'review/reference_dependency/mpmath-1.3.0-py3-none-any.whl'
expected = 'a0b2b9fe80bbcd81a6647ff13108738cfb482d481d826cc0e02f5b35e5c88d2c'
assert hashlib.sha256(wheel.read_bytes()).hexdigest() == expected
sys.path.insert(0,str(wheel)); import mpmath as mp
mp.mp.dps = 100
out = root / 'review/audit_beta_three_way'
rows = list(csv.DictReader((out/'cases.csv').open(encoding='utf-8')))
results=[]; started=time.time()
for i,row in enumerate(rows,1):
    # R reads the same decimal into an IEEE double; use that exact binary value.
    a,b,lo,hi=(mp.mpf(float(row[k])) for k in ('a','b','lo','hi'))
    if lo==0 and hi==1:
        logp=mp.mpf(0);method='full_support'
    elif a==1:
        v=b*mp.log1p(-lo)
        logp=v if hi==1 else v+mp.log(-mp.expm1(b*(mp.log1p(-hi)-mp.log1p(-lo))))
        method='closed_a1'
    elif b==1:
        v=a*mp.log(hi)
        logp=v if lo==0 else v+mp.log(-mp.expm1(a*(mp.log(lo)-mp.log(hi))))
        method='closed_b1'
    else:
        if (lo+hi)/2 > a/(a+b):
            probability=mp.betainc(b,a,1-hi,1-lo,regularized=True)
            method='high_precision_complement_interval'
        else:
            probability=mp.betainc(a,b,lo,hi,regularized=True)
            method='high_precision_lower_interval'
        if not mp.isfinite(probability) or probability<=0: raise RuntimeError('Invalid reference '+row['id'])
        logp=mp.log(probability)
    results.append(dict(row,ReferenceLogP=mp.nstr(logp,100),ReferenceMethod=method,PrecisionDigits=100))
    if i%50==0: print('HIGH_PRECISION_REFERENCE',i,'/',len(rows),flush=True)
with (out/'high_precision_reference.csv').open('w',encoding='utf-8',newline='') as f:
    w=csv.DictWriter(f,fieldnames=results[0].keys());w.writeheader();w.writerows(results)
info=dict(status='PASS_REFERENCE_GENERATED',cases=len(results),precision_digits=100,mpmath_version=mp.__version__,wheel_sha256=expected,input_semantics='exact IEEE binary64 values parsed from 17-digit decimal case table',elapsed_seconds=time.time()-started,formal_research_fits=0)
(out/'high_precision_reference_status.json').write_text(json.dumps(info,indent=2)+chr(10),encoding='utf-8')
print(json.dumps(info),flush=True)
