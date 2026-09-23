import csv,json,re,sys,itertools
from pathlib import Path
from pypdf import PdfReader
root=Path(sys.argv[1]);out=Path(sys.argv[2])
with (root/'input/sites.csv').open(encoding='utf-8-sig',newline='') as f: species=[r['Species'] for r in csv.DictReader(f)]
checks=[]
for route,tw in itertools.product(['binary','joint_bb'],['record_equal','species_equal']):
 name=f'species_predictions_{route}_{tw}.pdf';reader=PdfReader(root/'figures'/name); texts=[p.extract_text() or '' for p in reader.pages]
 missing=[]; modelmissing=[]
 for i,text in enumerate(texts):
  for s in species[i*42:(i+1)*42]:
   if s.replace('_',' ') not in text:missing.append({'page':i+1,'species':s})
  for m in ['Null','M1','M2','M3']:
   if not re.search(r'\b'+m+r'\b',text):modelmissing.append({'page':i+1,'model':m})
 checks.append(dict(file=name,expected_species=len(species),pages=len(texts),missing_species_labels=missing,missing_model_labels=modelmissing,pass_check=not missing and not modelmissing))
for name in ['ROC_curves.pdf','calibration_bins.pdf','quantitative_predicted_observed.pdf']:
 texts=[p.extract_text() or '' for p in PdfReader(root/'figures'/name).pages]
 missing=[{'page':i+1,'model':m} for i,text in enumerate(texts) for m in ['Null','M1','M2','M3'] if not re.search(r'\b'+m+r'\b',text)]
 checks.append(dict(file=name,pages=len(texts),missing_model_labels=missing,pass_check=not missing))
result={'status':'PASS' if all(x['pass_check'] for x in checks) else 'FAIL','checks':checks}
(out/'pdf_page_label_check.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(result,ensure_ascii=False,indent=2));sys.exit(0 if result['status']=='PASS' else 1)
