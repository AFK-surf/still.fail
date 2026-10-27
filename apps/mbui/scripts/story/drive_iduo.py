# The drive of film 1 on an iPhone Duo (scripts/motion/story-iduo.drive), made from the Pixel Fold one (drive.py):
# folded, its outer screen (466 x 678 points, its status bar down its right side), compact; opened, its inner screen
# (890 x 626), regular both ways, the fold upright down its middle: folded, its outer screen (411 x 900 dp),
# asked and sent with the keyboard up (the system's bars say it, as Android does); unfolded once the answer is there,
# the inner screen (791 x 820) open flat; 合并 tapped. `at` marks say when each thing happened, for what is drawn over.
import json
TOP, NAV, KB = 0, 20, 300
L = ["# Film 1 of still.fail in use on an iPhone Duo (made by scripts/story/drive_iduo.py; story scripts/story/iduo.json).", "timeout 45000", "at start"]
RIGHT = [80]
def bars(top, bottom, fold=None, size=None):
    m = {"bars": {"top": top, "bottom": bottom, "left": 0, "right": RIGHT[0]}}
    if size: m["size_class"] = {"width": size[0], "height": size[1]}
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
L += ["resize 466 678", bars(TOP, NAV, {"hinge": "none", "divisions": []}, ("compact", "regular")), "until 发消息", "wait 1000", "at tap@390,250", "tapxy 390 250", "wait 900",
      "at tap=发消息", "tap 发消息", "at kb-up"] + kb(0, KB) + ["wait 450"]
for w, pause in (("登录页", 420), ("暗色模式下", 480), ("按钮看不清", 380), ("，修一下", 650)):
    L += [f"at type={w}", f"type {w}", f"wait {pause}"]
L += ["at tap=send", "tap icon:arrow-up", "wait 150", "at kb-down"] + kb(KB, 0) + ["at working",
      "until 4.5 以上", "at answer", "wait 1500", "at swipe", "at drag@220,290,-180,0,450", "drag 220 290 -180 0 450", "wait 1100", "at unfold", "resize 890 626", 'system {"bars": {"top": 0, "bottom": 20, "left": 0, "right": 80}, "size_class": {"width": "regular", "height": "regular"}, "fold": {"hinge": "open", "divisions": [{"x": 445, "y": 0, "w": 0, "h": 626}]}}',
      "wait 1300", "wait 1200",
      "at pic", "at tap@514,476", "tapxy 514 476", "wait 2000", "at back", "back", "wait 800",
      "at scroll", "at drag@560,487,0,-320,420", "drag 560 487 0 -320 420", "wait 900", "at tap=合并", "tap =合并", "until 4f2a9c1", "at merged", "wait 3200", "at end"]
import os
open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../motion/story-iduo.drive"), "w").write("\n".join(L) + "\n")
