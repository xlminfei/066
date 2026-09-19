"""Bounded process identity/adoption tests using only short dummy processes."""
import subprocess
import sys
import time
from process_identity import AdoptedProcess,identity,same_live_process,matching_processes
from controller_lock import acquire_controller_lock

child=subprocess.Popen([sys.executable,"-c","import time; time.sleep(3)","job_probe","outcome","model"])
try:
    expected=identity(child.pid)
    assert expected and same_live_process(expected)
    adopted=AdoptedProcess(child.pid,"job_probe",["outcome","model"])
    assert [x["pid"] for x in matching_processes("job_probe",["outcome","model"])]==[child.pid]
    assert adopted.poll() is None
    try:AdoptedProcess(child.pid,"job_probe",["wrong","model"])
    except RuntimeError:pass
    else:raise AssertionError("Mismatched job was adopted")
    changed={**expected,"start_ticks":expected["start_ticks"]+1}
    assert not same_live_process(changed)
    child.wait(timeout=5)
    assert adopted.poll()==0
    assert not same_live_process(expected)
finally:
    if child.poll() is None:child.terminate();child.wait(timeout=5)
print("EXACT_PROCESS_ADOPTION_AND_PID_REUSE_GUARDS_PASS")
lock=acquire_controller_lock("/task/dummy/probe","test")
code='from controller_lock import acquire_controller_lock\ntry:\n acquire_controller_lock("/task/dummy/probe","test")\nexcept RuntimeError:\n print("LOCK_CONTENDER_REJECTED")\nelse:\n raise RuntimeError("duplicate controller lock accepted")'
subprocess.run([sys.executable,"-c",code],check=True)
lock.close()
subprocess.run([sys.executable,"-c",'from controller_lock import acquire_controller_lock; h=acquire_controller_lock("/task/dummy/probe","test");print("LOCK_RELEASE_AND_REACQUIRE_PASS")'],check=True)
