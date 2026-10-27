// What is drawn over what: strata (still.fail's apps/mbui/docs/strata.md). In a stratum, what is built later is drawn
// over what is built before it (a ZStack's order); what crosses strata says which it is in, by its name, never a
// number.
//
// A page's, bottom to top: its content (a list, a page's body), what floats over it (a composer, a bottom bar), what
// flies (Flying: from one place of the page to another, over where it set out from and where it lands, under what
// covers either), its bars (Bar), its cover (Cover: what is let go over it hinted over all of it) with what stays over
// it (OverCover: the composer what is let go goes into), the handles of words picked (an editor's, over everything of
// its layer). Over the page, the layers opened over it (overlay.mbt), each its scrim, what is lifted over the scrim
// (OverScrim: a row held for its menu) and what it holds.

///|
/// The stratum node `i` is drawn in (Ctx::stratum).
pub(all) enum Stratum {
  /// on its way from one place of its page to another (the words and files sent from the composer to their message):
  /// over everything built after it, under the next Bar or Cover painted after it and the layers opened over the page
  Flying
  /// a page's bar: over what flies built before it, as over its content
  Bar
  /// over all of a page (a hint of what is let go there): over what flies and the bars built before it, under what is
  /// OverCover
  Cover
  /// over the page's Cover where one is up (the composer what is let go goes into), in its place where none is
  OverCover
  /// over the scrim of the modal layer up (what a menu is of, held, standing out of what the menu dims, as iOS's
  /// context menu has it) and under what that layer holds; in its place where no layer with a scrim is up
  OverScrim
}

///|
/// Drawn's `z`: over its siblings (Ctx::put_over), and the strata put off to be painted later.
let z_siblings : Int = 1

///|
let z_flying : Int = 2

///|
let z_over_scrim : Int = 3

///|
let z_over_cover : Int = 4

///|
/// Node `i` drawn in stratum `s`. Tapped where it is laid out, in its place among the rest; drawn as its stratum is:
/// what is put off (Flying, OverCover, OverScrim) the window its clip where it is painted at the frame's end, the
/// clip of what it is painted over where that is painted.
pub fn Ctx::stratum(self : Ctx, i : Int, s : Stratum) -> Unit {
  match s {
    Flying => {
      // (painted after the rest, out of what a part kept draws: kept_part.mbt)
      part_live()
      self.drawn_of(i).z = z_flying
    }
    OverScrim => {
      part_live()
      self.drawn_of(i).z = z_over_scrim
    }
    // (put off only while a cover is up: what the cover is in is painted live then, Cover)
    OverCover => self.drawn_of(i).z = z_over_cover
    Bar => self.nodes[i].mark = 1
    Cover => {
      part_live()
      self.nodes[i].mark = 2
      dr.covers.push(i)
    }
  }
}

///|
/// What flies (Flying), put off till now: painted, over what was painted before (a stratum over it about to be).
fn Ctx::land_flying(self : Ctx) -> Unit {
  if dr.mode != 0 || dr.overlaying || dr.raising || dr.covering {
    return
  }
  self.raise_flying()
  self.paint_overlays()
}

///|
/// What is OverCover, once a cover is painted: each as it looks, over it.
fn Ctx::paint_over_cover(self : Ctx) -> Unit {
  if dr.over_cover.is_empty() || dr.covering {
    return
  }
  dr.covering = true
  let was = dr.mode
  dr.mode = mode_draw
  let todo = dr.over_cover.copy()
  dr.over_cover.clear()
  for p in todo {
    let (i, alpha) = p
    self.paint(i, alpha)
  }
  dr.mode = was
  dr.covering = false
}
