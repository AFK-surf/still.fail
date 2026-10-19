#!/usr/bin/env python3
"""A scripted run's conversation with its core (MBUI_CORE_TRACE=1: CORETRACE lines on a flow's log, e2e/run.sh) made a
test's: e2e/traces/NAME.trace, and src/sfreplay/trace_NAME_wbtest.mbt holding it (`trace_NAME`), for a Tester to give
again (src/core/replay.mbt). Bytes beside a message over MAX_BYTES (16 KB) are left out (a picture comes as none).

  scripts/trace.py out/e2e/mac/03-send-text.log [NAME]
"""
import json, os, re, sys

MAX_BYTES = int(os.environ.get("MAX_BYTES", 16384))
src = sys.argv[1]
name = sys.argv[2] if len(sys.argv) > 2 else re.sub(r"^\d+-", "", os.path.basename(src).rsplit(".", 1)[0])
ident = re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
lines = []
for line in open(src, encoding="utf-8", errors="replace"):
    i = line.find("CORETRACE ")
    if i < 0:
        continue
    ev = json.loads(line[i + 10:])
    if len(ev.get("b", "")) > MAX_BYTES * 2:
        del ev["b"]
    lines.append(json.dumps(ev, ensure_ascii=False, separators=(",", ":")))
if not lines:
    sys.exit(f"trace.py: no CORETRACE lines in {src} (was the run's app given MBUI_CORE_TRACE=1?)")
os.makedirs(f"{root}/e2e/traces", exist_ok=True)
with open(f"{root}/e2e/traces/{name}.trace", "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
with open(f"{root}/src/sfreplay/trace_{ident}_wbtest.mbt", "w", encoding="utf-8") as f:
    f.write(f"// e2e/traces/{name}.trace, made by scripts/trace.py from {os.path.basename(src)}: not edited by hand.\n\n")
    f.write(f"///|\nlet trace_{ident} : String =\n")
    for l in lines:
        f.write(f"  #|{l}\n")
print(f"{len(lines)} messages: e2e/traces/{name}.trace, src/sfreplay/trace_{ident}_wbtest.mbt")
