# The story (story.json) with its pictures in it: login.html as it was (改前) and as fixed (改后), drawn by Chrome.
import base64, json, os, subprocess, sys
here = os.path.dirname(os.path.abspath(__file__))
chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
story = json.load(open(os.path.join(here, sys.argv[1])))
# (a story in English: its pictures' names and the page's words in it)
en = story.get("lang") == "en"
words = {"登录 Acme": "Sign in to Acme", "欢迎回来": "Welcome back", "登录": "Sign in", "忘记密码？": "Forgot password?"}
pics = {}
kinds = [(("before.png" if en else "改前.png"), "before"), (("after.png" if en else "改后.png"), "after")]
# (a story whose agent fixes it again: the page as fixed the second time, its link brightened)
second = "after-2.png" if en else "改后-2.png"
if any(f.get("name") == second for steps in story.get("sent", []) for s in steps for f in s.get("post", {}).get("files", [])):
    kinds.append((second, "after after2"))
for name, kind in kinds:
    html = os.path.join(here, f"_{kind.split()[-1]}.html")
    page = open(os.path.join(here, "login.html")).read().replace("KIND", kind)
    if en:
        for zh, w in words.items():
            page = page.replace(">" + zh + "<", ">" + w + "<")
    open(html, "w").write(page)
    out = os.path.join(here, f"_{kind.split()[-1]}.png")
    subprocess.run([chrome, "--headless=new", "--hide-scrollbars", f"--screenshot={out}", "--window-size=390,780",
                    "--force-device-scale-factor=2", "file://" + html], check=True, capture_output=True)
    pics[name] = base64.b64encode(open(out, "rb").read()).decode()
story["pictures"] = pics
json.dump(story, open(sys.argv[2], "w"), ensure_ascii=False)
print("story:", sys.argv[2], {k: len(v) for k, v in pics.items()})
