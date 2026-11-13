// Comma's Badge and Tag (clients/packages/ui Badge, Tag) as nodes of the window's tree: words on a utility colour's
// ground in its edge, a pill or a rounded box; a Tag's ✕ pressed to take it away.

///|
/// A badge's or a tag's colour (Comma's BadgeColor; a Tag takes the first five).
#derive(Eq, Debug)
pub(all) enum Tone {
  Gray
  Brand
  Error
  Warning
  Success
  Blue
  Indigo
  Purple
  Pink
  Orange
}

///|
/// A badge's shape and fill (Comma's BadgeType): a pill in the tone's colours or edged on the page, a rounded box so,
/// or the modern one (edged on the page, with the xs shadow).
#derive(Eq, Debug)
pub(all) enum BadgeKind {
  PillColor
  PillOutline
  BadgeColor
  BadgeModern
}

///|
/// A badge's size (Comma's BadgeSize).
#derive(Eq, Debug)
pub(all) enum BadgeSize {
  BadgeSm
  BadgeMd
  BadgeLg
}

///|
/// A tone's utility colours: its 50 (ground), 200 (edge), 300 (outline's edge), 700 (words).
fn Tone::utility(self : Tone, c : Colors) -> (Int64, Int64, Int64, Int64) {
  match self {
    Gray => (c.utility_gray_50, c.utility_gray_200, c.utility_gray_300, c.utility_gray_700)
    Brand => (c.utility_brand_50, c.utility_brand_200, c.utility_brand_300, c.utility_brand_700)
    Error => (c.utility_error_50, c.utility_error_200, c.utility_error_300, c.utility_error_700)
    Warning => (c.utility_warning_50, c.utility_warning_200, c.utility_warning_300, c.utility_warning_700)
    Success => (c.utility_success_50, c.utility_success_200, c.utility_success_300, c.utility_success_700)
    Blue => (c.utility_blue_50, c.utility_blue_200, c.utility_blue_300, c.utility_blue_700)
    Indigo => (c.utility_indigo_50, c.utility_indigo_200, c.utility_indigo_300, c.utility_indigo_700)
    Purple => (c.utility_purple_50, c.utility_purple_200, c.utility_purple_300, c.utility_purple_700)
    Pink => (c.utility_pink_50, c.utility_pink_200, c.utility_pink_300, c.utility_pink_700)
    Orange => (c.utility_orange_50, c.utility_orange_200, c.utility_orange_300, c.utility_orange_700)
  }
}

///|
/// A badge of `kind` and `size` in `tone`: (ground, edge, words).
fn badge_looks(kind : BadgeKind, tone : Tone, c : Colors) -> (Int64, Int64, Int64) {
  let (fifty, two, three, seven) = tone.utility(c)
  match kind {
    PillColor | BadgeColor => (fifty, two, seven)
    PillOutline | BadgeModern =>
      if tone == Gray {
        (c.bg_primary, c.border_primary, seven)
      } else {
        (c.bg_primary, three, seven)
      }
  }
}

///|
/// Comma's badge in `parent`: `label` its words, in `tone`, of `kind` and `size`; `dot`: a dot in the tone's words'
/// colour before them. Read out as its words. The node.
#callsite(autofill(loc))
pub fn badge_node(
  parent : @view.View,
  label : () -> String,
  tone? : Tone = Gray,
  kind? : BadgeKind = PillColor,
  size? : BadgeSize = BadgeSm,
  dot? : Bool = false,
  loc~ : SourceLoc,
) -> @view.View {
  let pill = kind is (PillColor | PillOutline)
  let (px, py, role) = match size {
    BadgeSm => (space_md, space_xxs, type_mini)
    BadgeMd => (10.0, space_xxs, type_small)
    BadgeLg => (space_lg, space_xs, type_small)
  }
  parent.box(made_for=loc, fn(b) {
    let look = fn() { badge_looks(kind, tone, colors()) }
    b
    .row(Is(true))
    .lines_up(Is(Some(Middle)))
    .gap(Is(space_xs))
    .padding(Is((px, py, px, py)))
    .radius(Is(if pill { 1.0e6 } else { radius_md }))
    .ground(By(fn() { look().0 }))
    .edge(By(fn() { (1.0, look().1) }))
    |> ignore
    if kind == BadgeModern {
      b.shadow(By(fn() { if is_dark() { shadow_dark_xs } else { shadow_xs } })) |> ignore
    }
    if dot {
      b.box(fn(d) {
        d.width(Is(Some(6.0))).height(Is(Some(6.0))).radius(Is(3.0)).shrink(Is(0.0)).ground(By(fn() { look().2 }))
        |> ignore
      })
      |> ignore
    }
    b.box(fn(w) { w.words(By(label), look=words_in(role, weight=weight_medium)).ink(By(fn() { look().2 })) |> ignore })
    |> ignore
  })
}

///|
/// Comma's tag in `parent`: `label` its words in `tone` (Gray, Brand, Error, Warning or Success), of `size`; with
/// `remove`, a ✕ after them that takes it away as it is pressed (read out a button "移除 `label`"). The node.
#callsite(autofill(loc))
pub fn tag_node(
  parent : @view.View,
  label : () -> String,
  tone? : Tone = Gray,
  size? : BadgeSize = BadgeMd,
  remove? : () -> Unit,
  loc~ : SourceLoc,
) -> @view.View {
  let (px, py, gap, role) = match size {
    BadgeSm => (space_md, space_xxs, space_xs, type_mini)
    BadgeMd => (10.0, space_xxs, space_xs, type_small)
    BadgeLg => (10.0, space_xs, space_sm, type_small)
  }
  parent.box(made_for=loc, fn(b) {
    let look = fn() {
      let c = colors()
      if tone == Gray {
        (c.bg_primary, c.border_primary, c.text_secondary)
      } else {
        let (fifty, two, _, seven) = tone.utility(c)
        (fifty, two, seven)
      }
    }
    b
    .row(Is(true))
    .lines_up(Is(Some(Middle)))
    .gap(Is(gap))
    .padding(Is((px, py, px, py)))
    .radius(Is(radius_md))
    .ground(By(fn() { look().0 }))
    .edge(By(fn() { (1.0, look().1) }))
    |> ignore
    b.box(fn(w) { w.words(By(label), look=words_in(role, weight=weight_medium)).ink(By(fn() { look().2 })) |> ignore })
    |> ignore
    match remove {
      Some(remove) =>
        b.box(fn(x) {
          let on = fn() { true }
          let hand = eased_by(x, fn() { lit(x, on) }, ms_state_change, ease_soft_in_out)
          x
          .padding(Is((space_xxs, space_xxs, space_xxs, space_xxs)))
          .radius(Is(radius_xs))
          .ground(By(fn() { alpha(colors().bg_secondary, hand.shown(x)) }))
          .says(By(fn() { Some(@view.said(Button, label="移除 " + label())) }))
          |> ignore
          presses_node(x, remove)
          // (Comma's XIcon, 12 across: two strokes corner to corner)
          x.box(fn(g) {
            g
            .width(Is(Some(12.0)))
            .height(Is(Some(12.0)))
            .lines(By(fn() {
              let c = colors()
              let ink = mix(c.text_tertiary, hand.shown(x), c.text_disabled)
              [
                @ui.line([(3.0, 3.0), (9.0, 9.0)], width=1.5, color=ink),
                @ui.line([(9.0, 3.0), (3.0, 9.0)], width=1.5, color=ink),
              ]
            }))
            |> ignore
          })
          |> ignore
          ring_node(x, fn() { radius_xs }, ink=focus_gray.1)
        })
        |> ignore
      None => ()
    }
  })
}
