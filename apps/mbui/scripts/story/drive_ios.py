# The drive of film 1 on the iPhone Duo simulator (scripts/motion/story-iduo-ios.drive): iOS draws its own bars,
# keyboard and tabs, and the screens are swapped by the simulator's SpringBoard (scripts/story/film_ios.sh, on
# "DRIVE LOG UNFOLD"). Folded, the outer screen: asked and sent; unfolded once the answer is there, the inner one:
# the picture opened and closed, 合并 tapped. `at` marks say when each thing happened; `log SHOT name` asks for stills.
import os, sys
stills = "stills" in sys.argv[1:]
L = ["# Film 1 of still.fail in use on the iPhone Duo simulator (made by scripts/story/drive_ios.py; story scripts/story/iduo.json).",
     "timeout 45000", "at start", "until 发消息", "wait 1500"]
def shot(n):
    return [f"log SHOT {n}", "wait 700"] if stills else []
L += shot("start") + ["drag 400 330 -260 0 350", "wait 1200"] + shot("chat")
L += ["at tap=发消息", "tap 发消息", "wait 900"] + shot("kb")
for w, pause in (("登录页", 420), ("暗色模式下", 480), ("按钮看不清", 380), ("，修一下", 650)):
    L += [f"at type={w}", f"type {w}", f"wait {pause}"]
L += shot("typed")
L += ["at tap=send", "tap icon:arrow-up", "wait 500", "at kb-down", "tapxy 250 140", "wait 600", "at working", "wait 2000"] + shot("working")
L += ["until 退出登录", "at answer", "wait 1500"] + shot("answer")
L += ["at unfold", "log UNFOLD", "wait 4500"] + shot("open")
L += ["at pic", "tap img:改后", "wait 2000"] + shot("pic") + ["at back", "back", "wait 900"]
L += ["at scroll", "dragon 0 -320 450 退出登录", "wait 900"] + shot("scrolled") + ["at tap=合并", "tap =合并", "until 4f2a9c1", "at merged", "wait 3200"] + shot("merged") + ["at end", "exit"]
name = "story-iduo-ios-stills" if stills else "story-iduo-ios"
open(os.path.join(os.path.dirname(os.path.abspath(__file__)), f"../motion/{name}.drive"), "w").write("\n".join(L) + "\n")
print(name)
