# What is drawn over what

Everything is drawn in a stratum. Within one, what is built later is drawn over what is built before it (a ZStack's
order); that is all most UI code needs. What has to be over or under something built in another order says which
stratum it is in by name (`@ui.Stratum`, `Ctx::stratum`), never a number. `Ctx::put_over` is only "over my siblings"
(a list's row over the other rows).

## The window (the shell, `sfapp/app.mbt`), bottom to top

1. The pages: Small's stack, the tape's or the columns' panels.
2. Pages over the whole window: a station's screen, the reader, the player, a file's preview, a visualization.
3. Search, ⌘K, the shortcuts.
4. Layers opened over all of it (`Ctx::overlay`: menus, sheets, popovers, dialogs), each later one over the ones
   before; in each, its scrim, then what is lifted over it (`OverScrim`: a row held for its menu), then what it holds.
5. Toasts.
6. The loupe, the window's own buttons.
7. What is over all of it (`OverLayers`): a chat's bar and composer while a picture flies from the chat into its viewer
   or back, as much as it has not got away from its thumbnail (under them, where it lands).

The shell builds them in this order; a layer (`Ctx::overlay`) is over everything built outside it.

## A page, bottom to top

1. Its content: a list, a page's body.
2. What floats over it: the composer, a bottom bar, a button over the list.
3. What flies (`Flying`): on its way from one place of the page to another, drawn in the higher of the two strata it
   goes between and under what covers either. The words, files and quotes sent fly from the composer to their
   message: over the composer, under the bar, as the list they land in is (frosted by it as the list is).
4. Its bars (`Bar`): over what flies built before them.
5. Its cover (`Cover`): over all of the page (a row of 文件 carried over a chat, the hint where it is let go); what
   stays over it says so (`OverCover`: the composer it is let go into), in its place when no cover is up.
6. The handles of words picked (an editor's): over everything of their layer.

Opening a layer over the page draws whatever flies on the page under it too.

## How it is drawn

`Flying`, `OverCover`, `OverScrim` and `OverLayers` are put off as they are painted (`drawn_paint`) and painted where the stratum
over them starts: what flies at the next `Bar` or `Cover` painted after it, a layer opened, or the frame's end;
`OverCover` once a cover is painted; `OverScrim` once a scrim is; `OverLayers` at the frame's end, after all of it.
What flies is never painted in its place, in what is drawn moved by a look of its own too: it is put off with the
moves of what holds it, and moved by them as it is painted (as Flutter's Hero and Compose's shared elements are drawn
in an overlay over the page, never in their place), so that nothing that records what is painted (a kept part, a
list's row: kept_part.mbt, kept_rows.mbt) holds any of it nor needs to know of it. Handles are over all of it (`raise_tops`). Tests:
`mbui/src/ui/strata_wbtest.mbt`, pair by pair; a Tester holds words seen whole (`Tester::hold_seen_whole`).
