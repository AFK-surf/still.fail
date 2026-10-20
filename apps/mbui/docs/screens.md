# The screens' tests (src/sfscreens)

still.fail's 87 screens (sffix's fixture modes, the screenshots' screens) are drawn in mbui's Tester over the text the
Mac recorded for each (screens/text-mac.textrec, Mini1's), at the times the Mac drew its frames, to the frame its
picture is of. Each is checked three ways:

- its last frame's hash is the one the Mac drew (the screen is what the app shows on the Mac);
- its draw list is its reference (src/sfscreens/__snapshot__/MODE.dl);
- its pixels, the draw list drawn offscreen on GitHub's macos-15 (the mbui-render workflow), are its reference
  (goldens/render/macos15/MODE.png), once the machine is the references' (goldens/render/macos15.txt: system, fonts);
- the corner rule (mbui's `Tester::corner_faults`) breaks as many times as src/sfscreens/corners_known_wbtest.mbt says:
  one more fails, one fewer fails too until the count there comes down (in the PR that fixed it).

## A PR that changes what a screen draws records it again, in that PR

1. On Mini1 (the Mac the text is kept from; an agent: `station_task` on Mini1 with `dir` the worktree, `back`
   `apps/mbui/screens` and `apps/mbui/src/sfscreens/__snapshot__`):

       bash apps/mbui/scripts/screens.sh rerecord MODE…        # no MODE: every screen

   It checks Mini1 is the Mac the text was kept from (screens/text-mac.txt), records the screens again, rewrites
   their draw lists and checks them. Commit screens/ and __snapshot__/.
2. Push; the PR's mbui-render run draws the new draw lists and says which pictures differ. Take its pictures as the
   references and commit them:

       bash apps/mbui/scripts/screens.sh refs

   Look at the pictures that changed before committing them (and show them in the PR).

A failing screen says which and with what command. A reference "out of date" (GitHub's image moved on: another
system or other fonts) is not a screen broken: every picture is made again from that run's artifact, in one PR, said
there.
