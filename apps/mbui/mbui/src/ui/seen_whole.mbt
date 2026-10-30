// Words seen whole: a test says words that nothing of their page may be drawn over while it walks (words sent, flying
// from the composer to their message: drawn in the Flying stratum, strata.mbt), and every frame the Tester draws
// meanwhile holds them to it. What is over them by its stratum may be: a page's bar or cover, a layer opened over the
// page, what is put over a scrim or over everything (and what is over the page from outside it, a toast). Anything
// else drawn over a glyph of them (a fill nearly whole, a picture, glass, words of another node), the test fails then,
// with what and where (the user, 2026-10-30: 「现在发消息飞出去会被其它东西盖住」).

///|
/// The words held seen whole ("" none) and what drew over them first.
// kept across runs: begun anew by each Tester (Tester::new), each test saying its own
let seen_whole : Ref[String] = Ref::new("")

///|
/// From now on, until said again, nothing of the page is drawn over the words `words` (a node's whole text) on any
/// frame drawn: what is over them by its stratum aside (strata.mbt); "" lets go.
pub fn Tester::hold_seen_whole(self : Tester, words : String) -> Unit {
  ignore(self)
  seen_whole.val = words
  if words != "" {
    inst_owners.track = true
  }
}

///|
/// Whether node `i` is drawn over the rest of the page by its stratum: in a bar, a cover, a layer opened over it, over
/// a scrim, over the layers, or in what flies itself.
fn Ctx::seen_whole_over(self : Ctx, i : Int) -> Bool {
  let mut q = i
  while q >= 0 {
    let n = self.nodes[q]
    if n.mark != 0 || n.portal {
      return true
    }
    match self.drawn_entry(q) {
      Some(e) if e.z >= z_flying => return true
      _ => ()
    }
    q = n.parent
  }
  false
}

///|
/// What the frame just drawn draws over a glyph of the words held (seen_whole), not by its stratum: its words, where.
fn Ctx::seen_whole_faults(self : Ctx, words : String) -> (String, Double, Double)? {
  let a = self.inst
  for k in 0..<self.ninst {
    let b = k * inst_size
    let kind = a[b + 5]
    if (kind != 1.0 && kind != 3.0 && kind != 7.0) || a[b + 11] < words_over_seen_least {
      continue
    }
    let o = inst_by(k)
    if o == Nobody || self.by_text(o) != words {
      continue
    }
    // (the glyph's middle, where it is not cut away)
    let px = a[b] + a[b + 2] / 2.0
    let py = a[b + 1] + a[b + 3] / 2.0
    if !in_inst_clip(a, b, px, py) {
      continue
    }
    for j in (k + 1)..<self.ninst {
      let oj = inst_by(j)
      // (what is in the words' own node; an old view's over the page by its stratum: the tree has no strata yet,
      // nothing of its over them by one)
      let over = match oj {
        Old(i) => self.seen_whole_over(i)
        _ => false
      }
      if self.by_in(oj, o) || over {
        continue
      }
      let bj = j * inst_size
      let kj = a[bj + 5]
      let glyph = (kj == 1.0 || kj == 3.0 || kj == 7.0) &&
        a[bj + 11] >= words_over_seen_least &&
        in_inst(a, bj, px, py)
      if glyph || words_over_hides(a, j, px, py) {
        return Some((self.by_said(oj), px, py))
      }
    }
  }
  None
}

///|
/// The rule held on the frame just drawn, while words are held seen whole: drawn over, the test fails at once.
fn Tester::hold_seen_whole_now(self : Tester) -> Unit {
  let words = seen_whole.val
  if words == "" {
    return
  }
  match g().seen_whole_faults(words) {
    Some((by, x, y)) => {
      let said = "words held seen whole (seen_whole.mbt) drawn over on a frame drawn \{self.w}×\{self.h} at " +
        "\{self.fake.time}: 「\{words}」 under 「\{by}」 at (\{x.round()}, \{y.round()})"
      println(said)
      abort(said)
    }
    None => ()
  }
}
