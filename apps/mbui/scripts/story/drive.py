# The drive of film 1 (scripts/motion/story-fix.drive) on a Pixel 10 Pro Fold: folded, its outer screen (411 x 900 dp),
# asked and sent with the keyboard up (the system's bars say it, as Android does); unfolded once the answer is there,
# the inner screen (791 x 820) open flat; 合并 tapped. `at` marks say when each thing happened, for what is drawn over.
import json
TOP, NAV, KB = 36, 24, 290
L = ["# Film 1 of still.fail in use on a foldable (made by scripts/story/drive.py; story scripts/story/fix.json).", "timeout 45000", "at start"]
def bars(top, bottom, fold=None):
    m = {"bars": {"top": top, "bottom": bottom, "left": 0, "right": 0}}
    if fold: m["fold"] = fold
    return "system " + json.dumps(m, ensure_ascii=False)
def kb(a, b, ms=300):
    # a step each frame (60 a second), each said on the log (at kb=H) for the keyboard drawn over it to follow
    out, n = [], round(ms / (1000 / 60))
    for i in range(1, n + 1):
        k = i / n; e = 1 - (1 - k) ** 3
        h = round(a + (b - a) * e, 1)
        # (a system step takes its frame: the next step is the next frame's)
        out += [f"at kb={h}", f"ime {h}", bars(TOP, max(h, NAV))]
    return out
L += ["resize 411 900", bars(TOP, NAV, {"hinge": "closed", "divisions": []}), "until 发消息", "wait 1200",
      "at tap=发消息", "tap 发消息", "at kb-up"] + kb(0, KB) + ["wait 450"]
for w, pause in (("登录页", 420), ("暗色模式下", 480), ("按钮看不清", 380), ("，修一下", 650)):
    L += [f"at type={w}", f"type {w}", f"wait {pause}"]
L += ["at tap=send", "tap icon:arrow-up", "wait 150", "at kb-down"] + kb(KB, 0) + ["at working",
      "until =合并", "at answer", "wait 1500", "at swipe", "at drag@300,330,-200,0,450", "drag 300 330 -200 0 450", "wait 1100",
      "at unfold", "resize 791 820", bars(32, NAV, {"hinge": "open", "divisions": [{"x": 395, "y": 0, "w": 0, "h": 820}]}),
      "wait 1300", "at tap@700,420", "tapxy 700 420", "wait 1300",
      "at pic", "at tap@334,600", "tapxy 334 600", "wait 2000", "at back", "back", "wait 800",
      "at scroll", "at drag@450,620,0,-340,420", "drag 450 620 0 -340 420", "wait 900", "at tap=合并", "tap =合并", "until 4f2a9c1", "at merged", "wait 3200", "at end"]
open(__file__.replace("drive.py", "../motion/story-fix.drive"), "w").write("\n".join(L) + "\n")
