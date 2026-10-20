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


# (a site's request as the run's app forwarded it (station.preview), kept as mbui keeps the site's own on the record
# (hostcall.mbt site_event_kept, site_body_kept): a credential's header (Authorization, Cookie, Set-Cookie, a name
# saying token, key, secret, auth, session, password, sig) and such a field of the query or the body "-": what a
# Tester's host gives in their place, the replayed app forwards the same)
def secret_name(name):
    n = name.lower()
    return n in ("cookie", "set-cookie") or any(w in n for w in ("auth", "token", "key", "secret", "session", "password", "sig"))


def query_kept(path):
    if "?" not in path:
        return path
    head, q = path.split("?", 1)
    fields = []
    for f in q.split("&"):
        if "=" in f and secret_name(f.split("=", 1)[0]):
            f = f.split("=", 1)[0] + "=-"
        fields.append(f)
    return head + "?" + "&".join(fields)


def json_kept(j):
    if isinstance(j, dict):
        return {k: ("-" if secret_name(k) else json_kept(v)) for k, v in j.items()}
    if isinstance(j, list):
        return [json_kept(x) for x in j]
    return j


def body_kept(b):
    s = b.decode("latin-1")
    try:
        j = json.loads(s)
    except ValueError:
        j = None
    if isinstance(j, dict):
        k = json_kept(j)
        if k == j:
            return b
        try:
            return json.dumps(k, ensure_ascii=False, separators=(",", ":")).encode("latin-1")
        except UnicodeEncodeError:
            # (a body that wrote characters past latin-1 as \uXXXX escapes: not written back, all of it "-")
            return b"-"
    if "=" in s and " " not in s and "\n" not in s:
        k = query_kept("?" + s)[1:]
        return b if k == s else k.encode("latin-1")
    return b"-" if secret_name(s) else b


def preview_kept(ev):
    out = ev.get("out")
    if not (isinstance(out, dict) and out.get("call") == "station.preview" and isinstance(out.get("params"), dict)):
        return ev
    p = out["params"]
    if isinstance(p.get("headers"), list):
        p["headers"] = [[h[0], "-"] if isinstance(h, list) and len(h) == 2 and secret_name(str(h[0])) else h for h in p["headers"]]
    if isinstance(p.get("path"), str):
        p["path"] = query_kept(p["path"])
    if isinstance(ev.get("b"), str):
        ev["b"] = body_kept(bytes.fromhex(ev["b"])).hex()
    return ev


lines = []
texts = []
for line in open(src, encoding="utf-8", errors="replace"):
    # (what the host answered, as its text recording kept it (MBUI_TEXT_RECORD=1): a Tester answers the same)
    t = line.find("TEXTREC ")
    if t >= 0:
        try:
            texts.append(json.dumps({"textrec": json.loads(line[t + 8:])}, ensure_ascii=False, separators=(",", ":")))
        except ValueError:
            pass
        continue
    i = line.find("CORETRACE ")
    if i < 0:
        continue
    ev = preview_kept(scrub(json.loads(line[i + 10:])))
    # (a step that named the run's own log (a flow's {LOG}: second-station reads the command off it) as the test writes
    # it, {LOG}: the test's step is the same in every run)
    if isinstance(ev.get("step"), str) and os.path.abspath(src) in ev["step"]:
        ev["step"] = ev["step"].replace(os.path.abspath(src), "{LOG}")
    # (what the app was started with: its account's tokens put as "-" as a migrate's are)
    if isinstance(ev.get("env"), dict) and "MBUI_CORE_ACCOUNT" in ev["env"]:
        try:
            ev["env"]["MBUI_CORE_ACCOUNT"] = json.dumps(scrub(json.loads(ev["env"]["MBUI_CORE_ACCOUNT"])), ensure_ascii=False, separators=(",", ":"))
        except ValueError:
            ev["env"]["MBUI_CORE_ACCOUNT"] = "-"
    # (a sign-in's callback, its code in it: not kept)
    if isinstance(ev.get("env"), dict) and "MBUI_AUTH_COMPLETE" in ev["env"]:
        ev["env"]["MBUI_AUTH_COMPLETE"] = "-"
    # (a frame the host kept, whole: what the app uploads of it is compared with it)
    if "still" not in ev and len(ev.get("b", "")) > MAX_BYTES * 2:
        # (how many there were kept: a part read comes as that many, so what reads on asks for the next)
        ev["bn"] = len(ev.pop("b")) // 2
    lines.append(json.dumps(ev, ensure_ascii=False, separators=(",", ":")))
lines += texts
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
