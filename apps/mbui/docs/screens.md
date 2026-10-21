# The screens' tests (src/sfscreens)

still.fail's 87 screens (sffix's fixture modes, the screenshots' screens) are drawn in mbui's Tester over the text the
Mac recorded for each (screens/text-mac.textrec, Mini1's), at the times the Mac drew its frames, to the frame its
picture is of. Each is checked to be idle there, and to break the corner rule (mbui's `Tester::corner_faults`) as many
times as src/sfscreens/corners_known_wbtest.mbt says: one more fails, one fewer fails too until the count there comes
down (in the PR that fixed it).

What a screen draws is not compared with mbui's own drawing of it: no kept draw list, no frame of the Mac's, no
offscreen picture (all three were mbui against mbui, and were taken out). What still.fail's screens are held to is
Android's app, the original.

A screen whose text the Mac has not given yet (a new screen, new words) fails saying so; record it on Mini1 (an agent:
`station_task` on Mini1 with `dir` the worktree, `back` `apps/mbui/screens`):

    bash apps/mbui/scripts/screens.sh rec MODE…
