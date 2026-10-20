#!/usr/bin/env python3
"""A scripted run's conversation with its core (MBUI_CORE_TRACE=1: CORETRACE lines on a flow's log, e2e/run.sh) made a
test's: e2e/traces/NAME.trace, and src/sfreplay/trace_NAME.mbt holding it (`@sfreplay.trace_NAME`), for a Tester to
give again (src/core/replay.mbt, src/sfreplay/steps.mbt). Bytes beside a message over MAX_BYTES (16 KB) are left out,
their length kept ("bn": they come as that many zeros, a picture as none it can decode). A sign-in's tokens (the values
of keys SECRET names) are put as "-": not even the local cloud's made-up account's are kept.

  scripts/trace.py out/e2e/mac/03-send-text.log [NAME]
"""
import json, os, re, sys

MAX_BYTES = int(os.environ.get("MAX_BYTES", 16384))
SECRET = re.compile(r"^(access|refresh|accessToken|refreshToken|idToken|id_token|token|secret|password|code_verifier)$", re.I)
src = sys.argv[1]
name = sys.argv[2] if len(sys.argv) > 2 else re.sub(r"^\d+-", "", os.path.basename(src).rsplit(".", 1)[0])
ident = re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def scrub(v):
    if isinstance(v, dict):
        return {k: ("-" if SECRET.match(k) and isinstance(x, str) else scrub(x)) for k, x in v.items()}
    if isinstance(v, list):
        return [scrub(x) for x in v]
    return v


lines = []
for line in open(src, encoding="utf-8", errors="replace"):
    i = line.find("CORETRACE ")
    if i < 0:
        continue
    ev = scrub(json.loads(line[i + 10:]))
    # (what the app was started with: its account's tokens put as "-" as a migrate's are)
    if isinstance(ev.get("env"), dict) and "MBUI_CORE_ACCOUNT" in ev["env"]:
        try:
            ev["env"]["MBUI_CORE_ACCOUNT"] = json.dumps(scrub(json.loads(ev["env"]["MBUI_CORE_ACCOUNT"])), ensure_ascii=False, separators=(",", ":"))
        except ValueError:
            ev["env"]["MBUI_CORE_ACCOUNT"] = "-"
    # (a frame the host kept, whole: what the app uploads of it is compared with it)
    if "still" not in ev and len(ev.get("b", "")) > MAX_BYTES * 2:
        # (how many there were kept: a part read comes as that many, so what reads on asks for the next)
        ev["bn"] = len(ev.pop("b")) // 2
    lines.append(json.dumps(ev, ensure_ascii=False, separators=(",", ":")))
if not lines:
    sys.exit(f"trace.py: no CORETRACE lines in {src} (was the run's app given MBUI_CORE_TRACE=1?)")
os.makedirs(f"{root}/e2e/traces", exist_ok=True)
with open(f"{root}/e2e/traces/{name}.trace", "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
with open(f"{root}/src/sfreplay/trace_{ident}.mbt", "w", encoding="utf-8") as f:
    f.write(f"// e2e/traces/{name}.trace, made by scripts/trace.py from {os.path.basename(src)}: not edited by hand.\n\n")
    f.write(f"///|\n/// What the app and its core said in the run, a line each.\npub let trace_{ident} : String =\n")
    for l in lines:
        f.write(f"  #|{l}\n")
print(f"{len(lines)} messages: e2e/traces/{name}.trace, src/sfreplay/trace_{ident}.mbt")
