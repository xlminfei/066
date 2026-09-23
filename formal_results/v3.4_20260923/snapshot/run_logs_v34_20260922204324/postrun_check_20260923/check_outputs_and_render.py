import csv,json,hashlib,itertools,math,subprocess,re,sys
from pathlib import Path
from collections import Counter,defaultdict
from concurrent.futures import ThreadPoolExecutor
from pypdf import PdfReader
from PIL import Image,ImageDraw
root=Path(sys.argv[1]); out=Path(sys.argv[2]); logs=out.parent
poppler=Path(r'C:\Users\minfei\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\poppler\Library\bin')
checks=[]
def record(name,ok,**detail):
 checks.append(dict(check=name,passed=bool(ok),**detail))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def readcsv(p):
 with p.open(encoding='utf-8-sig',newline='') as f:return list(csv.DictReader(f))
def table(name):return readcsv(root/'results'/name)
def key(rows,cols):return [tuple(x[c] for c in cols) for x in rows]
def grid(name,rows,cols,expected):
 actual=key(rows,cols); record(name,len(actual)==len(set(actual)) and set(actual)==set(expected),rows=len(actual),expected=len(expected),missing=len(set(expected)-set(actual)),extra=len(set(actual)-set(expected)))
models=['Null','M1','M2','M3']; routes=['binary','joint_bb']; weight=['record_equal','species_equal']; designs={'fivefold':5,'tenfold':10}
status=json.loads((root/'review'/'final_v3_status.json').read_text()); audit=json.loads((root/'review'/'audit_v3.json').read_text())
record('final_status',status['status'] in ['COMPLETE','COMPLETE_WITH_REVIEW_FLAGS'],status=status['status'])
record('final_audit',audit['status']=='PASS' and audit['fits_passed']==audit['fits_checked']==audit['expected_tasks']==256 and not audit['issues'],**audit)
manifest=readcsv(root/'review'/'derived_outputs_manifest.csv'); bad=[x['Path'] for x in manifest if not (root/x['Path']).is_file() or sha(root/x['Path'])!=x['SHA256']]
actual_outputs={p.relative_to(root).as_posix() for d in ['results','figures','reports'] for p in (root/d).rglob('*') if p.is_file()}
record('derived_output_hashes_and_universe',not bad and actual_outputs=={x['Path'] for x in manifest},files=len(manifest),bad=bad,unlisted=sorted(actual_outputs-{x['Path'] for x in manifest}))
frozen=json.loads((logs/'frozen_source_inputs.json').read_text())['files']; changed=[x['path'] for x in frozen if sha(root/x['path'])!=x['sha256']]
record('frozen_code_inputs_config',not changed,files=len(frozen),changed=changed)
plan=readcsv(root/'runs'/'run_plan.csv'); rec=readcsv(root/'review'/'fit_audit.csv')
expected_plan=[('full',r,m,t,'') for r,m,t in itertools.product(routes,models,weight)]+[(d,r,m,t,str(f)) for d,k in designs.items() for r,m,t,f in itertools.product(routes,models,weight,range(1,k+1))]
for label,rows in [('plan',plan),('fit_audit',rec)]:grid(label,rows,['Design','Route','Model','TrainWeighting','Fold'],expected_plan)
record('fit_audit_all_statuses',all(x['Pass']==x['IdentityPass']==x['PredictionPass']=='TRUE' for x in rec))
fit_paths=[root/'runs'/'fits'/('__'.join([x['Route'],x['Model'],x['TrainWeighting'],'full' if x['Design']=='full' else x['Design']+'_f'+x['Fold']]))/'fit.rds' for x in plan]
actual_fits=list((root/'runs'/'fits').glob('*/fit.rds'))
record('256_checkpoint_files',set(fit_paths)==set(actual_fits) and all(p.stat().st_size>0 for p in fit_paths),count=len(actual_fits),total_bytes=sum(p.stat().st_size for p in actual_fits))
counts={p.name:len(readcsv(p)) for p in (root/'results').glob('*.csv')}
obs=readcsv(root/'input'/'observations.csv'); sites=readcsv(root/'input'/'sites.csv')
active={'joint_bb':[x['RecordID'] for x in obs if not(x['Type']=='interval' and float(x['Lower'])==0 and float(x['Upper'])==1)],'binary':[x['RecordID'] for x in obs if x['Type']!='interval' or float(x['Upper'])<=.5 or float(x['Lower'])>=.5]}
evidence=table('cv_record_predictions.csv'); expected_ev=[(d,r,m,t,rid) for d,r,m,t in itertools.product(designs,routes,models,weight) for rid in active[r]]
grid('OOF_4880_record_identity',evidence,['Design','Route','Model','TrainWeighting','RecordID'],expected_ev)
record('OOF_formal_finite_log_scores',all(x['RunPurpose']=='formal' and math.isfinite(float(x['LogPredictiveDensityRaw'])) for x in evidence))
full=table('full_panel_predictions.csv'); expected_full=[(sp['Species'],r,m,t) for sp in sites for r,m,t in itertools.product(routes,models,weight)]
grid('full_panel_5840_identity',full,['Species','Route','Model','TrainWeighting'],expected_full)
summary=table('cv_metrics_summary.csv'); summary_cols=['Design','Route','Model','TrainWeighting','EvalWeighting']; expected_summary=list(itertools.product(designs,routes,models,weight,weight))
grid('64_CV_summary_groups',summary,summary_cols,expected_summary)
fold_metrics=table('cv_fold_metrics.csv'); expected_fold=[(d,r,m,t,e,str(f)) for d,k in designs.items() for r,m,t,e,f in itertools.product(routes,models,weight,weight,range(1,k+1))]
grid('480_fold_metric_groups',fold_metrics,summary_cols+['Fold'],expected_fold)
model_comp=table('model_vs_null.csv'); train_comp=table('training_method_comparisons.csv')
grid('48_model_comparison_groups',model_comp,summary_cols,list(itertools.product(designs,routes,models[1:],weight,weight)))
grid('32_training_comparison_groups',train_comp,['Design','Route','Model','EvalWeighting'],list(itertools.product(designs,routes,models,weight)))
record('80_overall_comparison_P_values_present',all(math.isfinite(float(x[c])) and 0<=float(x[c])<=1 for x in model_comp+train_comp for c in ['P_approx','P_BH']))
roc=table('roc_coordinates.csv'); roc_keys=set(key(roc,['Design','Model','TrainWeighting','EvalWeighting','Fold'])); expected_roc={(d,m,t,e,str(f)) for d,k in designs.items() for m,t,e,f in itertools.product(models,weight,weight,range(1,k+1))}
record('240_ROC_curve_groups',roc_keys==expected_roc,curves=len(roc_keys),rows=len(roc))
cal=table('calibration_bins.csv'); record('32_calibration_groups',set(key(cal,['Design','Model','TrainWeighting','EvalWeighting']))==set(itertools.product(designs,models,weight,weight)),bins=len(cal),interval_statuses=dict(Counter(x['IntervalStatus'] for x in cal)))
qs=table('quantitative_bias_summary.csv'); grid('32_quantitative_bias_groups',qs,summary_cols,list(itertools.product(designs,['joint_bb'],models,weight,weight)))
qsrc=table('quantitative_plot_source.csv'); points=[x['RecordID'] for x in obs if x['Type'] in ['count','exact']]
grid('4640_quantitative_plot_rows',qsrc,['Design','Model','TrainWeighting','EvalWeighting','RecordID'],[(d,m,t,e,i) for d,m,t,e in itertools.product(designs,models,weight,weight) for i in points])
plot_source=readcsv(root/'figures'/'species_prediction_plot_source.csv'); grid('5840_species_plot_rows',plot_source,['Species','Route','Model','TrainWeighting'],expected_full)
full_map={tuple(x[c] for c in ['Species','Route','Model','TrainWeighting']):x for x in full}
record('species_plot_values_match_full_prediction_table',all(all(x[c]==full_map[tuple(x[n] for n in ['Species','Route','Model','TrainWeighting'])][c] for c in full[0]) for x in plot_source))
variation=[]
for r,m,t in itertools.product(routes,models,weight):
 z=[x for x in full if (x['Route'],x['Model'],x['TrainWeighting'])==(r,m,t)]; vals=[float(x['Point']) for x in z]
 variation.append(dict(Route=r,Model=m,TrainWeighting=t,UniquePointValues=len(set(vals)),Minimum=min(vals),Maximum=max(vals),Warnings=sum(bool(x['WarningCodes']) for x in z)))
record('Null_constant_and_predictor_models_variable',all(x['UniquePointValues']==1 if x['Model']=='Null' else x['UniquePointValues']>1 for x in variation))
ppc=table('training_ppc_summary.csv'); flags=[x for x in ppc if x['Status']=='REVIEW_REQUIRED']
ppc_expected=[(r,m,t,e,s,stat) for r,m,t,e in itertools.product(routes,models,weight,weight) for s in (['classified'] if r=='binary' else ['count','exact','all_point']) for stat in ['Mean','SD','ZeroFraction','OneFraction']]
grid('256_PPC_statistic_groups',ppc,['Route','Model','TrainWeighting','EvalWeighting','Subset','Statistic'],ppc_expected)
record('PPC_flags_consistent_with_bounds',all((x['Status']=='REVIEW_REQUIRED')==(float(x['Observed'])<float(x['PPC_Lower95']) or float(x['Observed'])>float(x['PPC_Upper95'])) for x in ppc),flag_count=len(flags),by_model_train={str(k):v for k,v in Counter((x['Model'],x['TrainWeighting']) for x in flags).items()})
expected_pdfs={'ROC_curves.pdf':8,'calibration_bins.pdf':8,'quantitative_predicted_observed.pdf':8,'training_ppc_summary.pdf':16,**{f'species_predictions_{r}_{t}.pdf':9 for r,t in itertools.product(routes,weight)}}
record('expected_PDF_file_set',{p.name for p in (root/'figures').glob('*.pdf')}==set(expected_pdfs))
render_dir=out/'rendered_pages'; render_dir.mkdir(exist_ok=True)
def inspect_pdf(item):
 name,expected=item; path=root/'figures'/name; reader=PdfReader(path,strict=True); text=[p.extract_text() or '' for p in reader.pages]
 target=render_dir/path.stem; target.mkdir(exist_ok=True)
 proc=subprocess.run([str(poppler/'pdftoppm.exe'),'-png','-r','96',str(path),str(target/'page')],capture_output=True,text=True)
 (target/'render_stderr.txt').write_text(proc.stderr,encoding='utf-8')
 images=sorted(target.glob('page-*.png')); image_rows=[]
 for p in images:
  with Image.open(p) as im:
   g=im.convert('L'); hist=g.histogram(); dark=sum(hist[:245]); image_rows.append(dict(file=str(p),width=im.width,height=im.height,nonwhite_fraction=dark/(im.width*im.height)))
 for i,t in enumerate(text):(target/f'page-{i+1:02d}.txt').write_text(t,encoding='utf-8')
 contacts=[]
 for begin in range(0,len(images),8):
  subset=images[begin:begin+8]; thumbs=[]
  for p in subset:
   with Image.open(p) as im:
    im=im.convert('RGB'); im.thumbnail((660,500)); thumbs.append((p,im.copy()))
  sheet=Image.new('RGB',(1360,math.ceil(len(thumbs)/2)*540),'#e4e4e4'); draw=ImageDraw.Draw(sheet)
  for j,(p,im) in enumerate(thumbs):
   x=(j%2)*680+10; y=(j//2)*540+25;sheet.paste(im,(x,y));draw.text((x,y-18),f'{path.stem} / {p.stem}',fill='black')
  cp=out/f'contact_{path.stem}_{begin//8+1}.jpg';sheet.save(cp,quality=92);contacts.append(str(cp))
 return dict(file=name,bytes=path.stat().st_size,pages=len(reader.pages),expected_pages=expected,render_exit=proc.returncode,render_stderr=proc.stderr,rendered_pages=len(images),nonempty_text_pages=sum(bool(t.strip()) for t in text),all_pages_nonblank=all(x['nonwhite_fraction']>.005 for x in image_rows),images=image_rows,contacts=contacts,sha256=sha(path),pass_check=len(reader.pages)==expected==len(images) and proc.returncode==0 and all(x['nonwhite_fraction']>.005 for x in image_rows))
with ThreadPoolExecutor(max_workers=4) as pool: pdfs=list(pool.map(inspect_pdf,expected_pdfs.items()))
for d in pdfs:record('PDF_render_'+d['file'],d['pass_check'],pages=d['pages'],render_exit=d['render_exit'],stderr=d['render_stderr'])
log=(logs/'05_formal_all.log').read_text(encoding='utf-8-sig',errors='replace'); warning_lines=[{'line':i+1,'text':line} for i,line in enumerate(log.splitlines()) if re.search(r'Warning|Exception|Error|FAILED|Rejecting initial|divergent',line)]
record('formal_log_256_fit_end_PASS',len(re.findall(r'^FIT_END .* PASS\s*$',log,re.M))==256,fit_end_pass=len(re.findall(r'^FIT_END .* PASS\s*$',log,re.M)),fit_start=len(re.findall(r'^FIT_START ',log,re.M)),audit_pass=len(re.findall(r'^AUDIT_FIT .* PASS\s*$',log,re.M)),warning_lines=len(warning_lines))
(out/'PPC_review_flags.json').write_text(json.dumps(flags,ensure_ascii=False,indent=2),encoding='utf-8')
with (out/'PPC_review_flags.csv').open('w',newline='',encoding='utf-8-sig') as f:w=csv.DictWriter(f,fieldnames=ppc[0].keys());w.writeheader();w.writerows(flags)
(out/'pdf_check.json').write_text(json.dumps(pdfs,ensure_ascii=False,indent=2),encoding='utf-8')
(out/'prediction_variation.json').write_text(json.dumps(variation,indent=2),encoding='utf-8')
(out/'warning_lines.json').write_text(json.dumps(warning_lines,ensure_ascii=False,indent=2),encoding='utf-8')
result=dict(status='PASS' if all(x['passed'] for x in checks) else 'FAIL',checks=checks,result_csv_counts=counts,ppc_flags=len(flags),pdf_files=len(pdfs),pdf_pages=sum(x['pages'] for x in pdfs),rendered_pages=sum(x['rendered_pages'] for x in pdfs),notes='Read-only verification of current outputs; no posterior fits or MCMC; rendering only. Visual review is recorded separately.')
(out/'structural_output_check.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in result.items() if k!='checks'},ensure_ascii=False,indent=2));print('FAILED_CHECKS',json.dumps([x for x in checks if not x['passed']],ensure_ascii=False));print('CONTACTS',json.dumps([c for d in pdfs for c in d['contacts']],ensure_ascii=False))
sys.exit(0 if result['status']=='PASS' else 1)
