// Comma's Button (clients/packages/ui Button: its hierarchies and sizes, styles.ts) as a node of the window's tree, made
// once: its ground, edge and words in the hierarchy's colours, going to their lit ones under the hand over Comma's
// state change (150 ms, surface-smooth-out); faded to the disabled ones while it cannot be pressed; the focus ring of
// its hierarchy (brand or grey) while the keyboard's focus is on it.

///|
/// A button's hierarchy (Comma's ButtonHierarchy).
#derive(Eq, Debug)
pub(all) enum Hierarchy {
  Primary
  SecondaryColor
  SecondaryGray
  TertiaryColor
  TertiaryGray
  LinkColor
  LinkGray
  Destructive
}

///|
/// A button's size (Comma's ButtonSize): Xs 32 high (a row's action in a panel), Sm 36, Md 40, Lg 44.
#derive(Eq, Debug)
pub(all) enum Size {
  Xs
  Sm
  Md
  Lg
}

///|
/// The height of a button of `size`.
pub fn Size::height(self : Size) -> Double {
  match self {
    Xs => space_4xl
    Sm => 36.0
    Md => 40.0
    Lg => 44.0
  }
}

///|
/// How far in its words stand from its ends.
fn Size::pad(self : Size) -> Double {
  match self {
    Xs => space_md
    Sm => space_lg
    Md => 14.0
    Lg => space_xl
  }
}

///|
/// Its words' role: Lg's the regular, the rest the small.
fn Size::type_role(self : Size) -> TypeRole {
  match self {
    Lg => type_regular
    _ => type_small
  }
}

///|
/// What a hierarchy is drawn in, at rest and lit: (ground, edge, words) each; 0 a colour said none (no ground, no edge).
fn looks(h : Hierarchy, c : Colors) -> ((Int64, Int64, Int64), (Int64, Int64, Int64)) {
  match h {
    Primary =>
      (
        (c.button_primary_bg, c.button_primary_border, c.button_primary_fg),
        (c.button_primary_bg_hover, c.button_primary_border_hover, c.button_primary_fg_hover),
      )
    SecondaryColor =>
      (
        (c.button_secondary_color_bg, c.button_secondary_color_border, c.button_secondary_color_fg),
        (c.button_secondary_color_bg_hover, c.button_secondary_color_border_hover, c.button_secondary_color_fg_hover),
      )
    SecondaryGray =>
      (
        (c.button_secondary_bg, c.button_secondary_border, c.button_secondary_fg),
        (c.bg_secondary, c.button_secondary_border, c.text_primary),
      )
    TertiaryColor =>
      (
        (alpha(c.button_tertiary_color_bg_hover, 0.0), 0L, c.button_tertiary_color_fg),
        (c.button_tertiary_color_bg_hover, 0L, c.button_tertiary_color_fg_hover),
      )
    TertiaryGray =>
      (
        (alpha(c.button_tertiary_bg_hover, 0.0), 0L, c.button_tertiary_fg),
        (c.button_tertiary_bg_hover, 0L, c.button_tertiary_fg_hover),
      )
    LinkColor => ((0L, 0L, c.button_tertiary_color_fg), (0L, 0L, c.button_tertiary_color_fg_hover))
    LinkGray => ((0L, 0L, c.button_tertiary_fg), (0L, 0L, c.button_tertiary_fg_hover))
    Destructive =>
      (
        (c.button_primary_error_bg, c.button_primary_error_border, c.button_primary_error_fg),
        (c.button_primary_error_bg_hover, c.button_primary_error_border_hover, c.button_primary_error_fg_hover),
      )
  }
}

///|
/// What it is drawn in while it cannot be pressed: (ground, edge, words).
fn disabled_looks(h : Hierarchy, c : Colors) -> (Int64, Int64, Int64) {
  match h {
    Primary | SecondaryColor | SecondaryGray | Destructive => (c.bg_disabled, c.border_secondary, c.text_disabled)
    TertiaryColor | TertiaryGray => (0L, 0L, c.text_disabled)
    LinkColor | LinkGray => (0L, 0L, c.text_disabled)
  }
}

///|
/// Whether it stands on the page with an edge and the xs shadow (its hierarchy's `shadow-xs`).
fn Hierarchy::raised(self : Hierarchy) -> Bool {
  self is (Primary | SecondaryColor | SecondaryGray | Destructive)
}

///|
/// Whether its focus ring is the grey one.
fn Hierarchy::gray(self : Hierarchy) -> Bool {
  self is (SecondaryGray | TertiaryGray | LinkGray)
}

///|
/// Comma's button in `parent`: `label` its words, `press` done as it is pressed, of `hierarchy` and `size`; `dot`: the
/// success dot before its words (dotLeading); `disabled` while it cannot be pressed (the disabled colours, taking no
/// press nor the focus). Read out a button named `label`. The node.
#callsite(autofill(loc))
pub fn button_node(
  parent : @view.View,
  label : () -> String,
  press : () -> Unit,
  hierarchy? : Hierarchy = Primary,
  size? : Size = Md,
  dot? : Bool = false,
  disabled? : () -> Bool = fn() { false },
  loc~ : SourceLoc,
) -> @view.View {
  let live = fn() { !disabled() }
  let link = hierarchy is (LinkColor | LinkGray)
  let corner = radius_md
  parent.box(made_for=loc, fn(v) {
    let hand = eased_by(v, fn() { lit(v, live) }, ms_state_change, ease_soft_in_out)
    let off = eased_by(v, disabled, ms_state_change, ease_soft_in_out)
    // (its ground, edge and words now: at rest to lit as far as the hand has gone, then to the disabled ones as far as
    // that has)
    let now = fn() {
      let c = colors()
      let (rest, on) = looks(hierarchy, c)
      let (dg, de, dw) = disabled_looks(hierarchy, c)
      let h = hand.shown(v)
      let o = off.shown(v)
      let one = fn(a : Int64, b : Int64, d : Int64) { mix(d, o, mix(b, h, a)) }
      (one(rest.0, on.0, dg), one(rest.1, on.1, de), one(rest.2, on.2, dw))
    }
    v
    .row(Is(true))
    .lines_up(Is(Some(Middle)))
    .lies_along(Is(Middle))
    .gap(Is(space_xs))
    .radius(Is(corner))
    .ground(By(fn() { now().0 }))
    .says(By(fn() { Some(@view.said(Button, label=label())) }))
    |> ignore
    if !link {
      v
      .height(Is(Some(size.height())))
      .padding(Is((size.pad(), 0.0, size.pad(), 0.0)))
      .edge(By(fn() { (if hierarchy.raised() { 1.0 } else { 0.0 }, now().1) }))
      |> ignore
    }
    if hierarchy.raised() {
      v
      .shadow(By(fn() {
        if disabled() {
          (0.0, 0.0, 0L)
        } else if is_dark() {
          shadow_dark_xs
        } else {
          shadow_xs
        }
      }))
      |> ignore
    }
    presses_node(v, press, on=live)
    if dot {
      let side = if size is (Xs | Sm) { 6.0 } else { 8.0 }
      v.box(fn(d) {
        d
        .width(Is(Some(side)))
        .height(Is(Some(side)))
        .radius(Is(side / 2.0))
        .shrink(Is(0.0))
        .ground(By(fn() { colors().fg_success_primary }))
        |> ignore
      })
      |> ignore
    }
    v.box(fn(w) {
      w.words(By(label), look=words_in(size.type_role(), weight=weight_medium)).ink(By(fn() { now().2 })) |> ignore
    })
    |> ignore
    ring_node(v, fn() { corner }, ink=if hierarchy.gray() { focus_gray.1 } else { focus_brand.1 })
  })
}
