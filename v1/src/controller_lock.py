"""Container-local lifetime lock; telemetry files are not synchronization locks."""
from pathlib import Path
import fcntl
import hashlib
import os

def acquire_controller_lock(root,kind):
    key=hashlib.sha256(str(Path(root)).encode()).hexdigest()[:20]
    path=Path("/tmp")/f"ratio_{kind}_{key}.lock"
    handle=path.open("a+")
    try:fcntl.flock(handle.fileno(),fcntl.LOCK_EX|fcntl.LOCK_NB)
    except BlockingIOError:
        handle.close()
        raise RuntimeError("Another controller holds the exclusive lifetime lock")
    handle.seek(0);handle.truncate();handle.write(str(os.getpid()));handle.flush()
    return handle
