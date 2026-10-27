# Stills of a story's film (out/film/story-<name>.mp4) laid in still.html: each at its moment, with its words.
import json, os, re, subprocess, sys, urllib.parse
here = os.path.dirname(os.path.abspath(__file__)); app = os.path.dirname(os.path.dirname(here))
name = sys.argv[1]
film = f"{app}/out/film/story-{name}.mp4"; out = f"{app}/out/stills"; os.makedirs(out, exist_ok=True)
log = open(f"{app}/out/story/{name}.log").read()
taps = {m[0]: m[1] for m in re.findall(r"DRIVE tap (\S+) at (\d+,\d+)", log)}
chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
for i, s in enumerate(json.load(open(f"{here}/{name}.stills.json"))):
    frame = f"{out}/_f{i}.png"
    subprocess.run(["/opt/homebrew/bin/ffmpeg", "-loglevel", "error", "-y", "-ss", str(s["t"]), "-i", film, "-frames:v", "1", frame], check=True)
    q = {k: v for k, v in s.items() if k not in ("t",)}
    if "tapon" in q: q["tap"] = taps[q.pop("tapon")]
    q["frame"] = "file://" + frame
    url = "file://" + here + "/still.html?" + urllib.parse.urlencode(q)
    subprocess.run([chrome, "--headless=new", "--hide-scrollbars", "--allow-file-access-from-files", f"--screenshot={out}/still-{i + 1}.png",
                    "--window-size=1920,1080", "--force-device-scale-factor=1", "--virtual-time-budget=1500", url], check=True, capture_output=True)
    print("still", i + 1, s["t"])
