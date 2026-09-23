import io,copy,json,zipfile

def check(copy_info):
 a,b=io.BytesIO(),io.BytesIO()
 with zipfile.ZipFile(a,'w') as z1,zipfile.ZipFile(b,'w') as z2:
  z1.writestr('first.txt','different preceding layout')
  shared=zipfile.ZipInfo('data.txt');z1.writestr(shared,'identical source data')
  z2.writestr(copy.copy(shared) if copy_info else shared,'identical source data')
 try:
  with zipfile.ZipFile(io.BytesIO(a.getvalue())) as z:
   assert z.read('data.txt')==b'identical source data'
  return True
 except zipfile.BadZipFile:return False
before=check(False);after=check(True);assert not before and after
print(json.dumps({'status':'PASS','old_shared_zipinfo_failure_reproduced':not before,'separate_zipinfo_objects_fix_verified':after}))
