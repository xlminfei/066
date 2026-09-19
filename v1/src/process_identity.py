"""Read Linux process identity without treating a recycled PID as the same task."""
from pathlib import Path

def identity(pid):
    path=Path(f"/proc/{int(pid)}")
    try:
        stat=(path/"stat").read_text()
        fields=stat.rsplit(")",1)[1].split()
        command=[part.decode("utf-8",errors="replace") for part in (path/"cmdline").read_bytes().split(b"\0") if part]
        return dict(pid=int(pid),ppid=int(fields[1]),state=fields[0],start_ticks=int(fields[19]),command=command)
    except (FileNotFoundError,ProcessLookupError):
        return None

def same_live_process(expected):
    current=identity(expected["pid"])
    return bool(current and current["state"]!="Z" and current["start_ticks"]==expected["start_ticks"]
                and current["command"]==expected["command"])

def matching_processes(script,arguments):
    matches=[]
    for path in Path("/proc").iterdir():
        if not path.name.isdigit():continue
        try:observed=identity(int(path.name))
        except (PermissionError,FileNotFoundError,ProcessLookupError):continue
        if not observed or observed["state"]=="Z":continue
        command=observed["command"]
        if any(token==script or token=="--file="+script for token in command) and command[-len(arguments):]==list(arguments):
            matches.append(observed)
    return matches

class AdoptedProcess:
    def __init__(self,pid,script,arguments):
        self.pid=int(pid)
        self.expected=identity(self.pid)
        if not self.expected or self.expected["state"]=="Z":raise RuntimeError("Cannot adopt a non-live process")
        command=self.expected["command"]
        script_matches=any(token==script or token=="--file="+script for token in command)
        if not script_matches or command[-len(arguments):]!=list(arguments):
            raise RuntimeError("Live process identity does not match the exact CV job")
    def poll(self):
        # Exit code is unavailable for a non-child. The queue separately requires a terminal R receipt.
        return None if same_live_process(self.expected) else 0

class NullLogHandle:
    def close(self):
        return None
