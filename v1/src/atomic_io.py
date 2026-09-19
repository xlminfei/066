"""Atomic status publication across a Windows bind mount with transient reader locks."""
from pathlib import Path
import json
import os
import sys
import time

def read_json(path,missing_ok=False,wait_seconds=3.0):
    """Retry transient visibility/partial-read failures without treating absence as completion."""
    path=Path(path)
    deadline=time.monotonic()+wait_seconds
    while True:
        try:
            return json.loads(path.read_text(encoding="utf-8-sig"))
        except (FileNotFoundError,PermissionError,json.JSONDecodeError,UnicodeDecodeError) as error:
            if time.monotonic()<deadline:
                time.sleep(.05)
                continue
            if missing_ok and isinstance(error,FileNotFoundError):return None
            raise

def atomic_json(path,value,critical=False,wait_seconds=3.0):
    path=Path(path)
    temporary=path.with_name(path.name+f".tmp.{os.getpid()}")
    payload=json.dumps(value,ensure_ascii=False,indent=2)
    deadline=time.monotonic()+wait_seconds
    while True:
        try:
            temporary.write_text(payload,encoding="utf-8")
            temporary.replace(path)
            return True
        except PermissionError:
            if time.monotonic()<deadline:
                time.sleep(.1)
                continue
            if critical:raise
            # Telemetry contention must not abandon already-launched model processes.
            print("STATUS_SNAPSHOT_DEFERRED",path.name,flush=True,file=sys.stderr)
            return False
