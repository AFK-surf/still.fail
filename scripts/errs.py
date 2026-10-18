import sys, json
n = 0
for line in sys.stdin:
    line = line.strip()
    if not line.startswith("{"):
        if "rror" in line:
            print(line)
        continue
    try:
        d = json.loads(line)
    except Exception:
        continue
    if d.get("level") != "error":
        continue
    n += 1
    if n > 40:
        continue
    p = d["path"].split("/src/")[-1]
    print("%s:%s: %s" % (p, d["loc"], d["message"]))
print("errors: %d" % n)
