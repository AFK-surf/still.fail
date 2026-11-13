// Comma's Avatar (clients/packages/ui avatar/Avatar) as a node of the window's tree: a circle on the avatar's ground,
// a person's initials on it in semibold, its ring the profile photo's edge; a dot at its foot's end while `online`
// says (green online, grey not).

///|
/// An avatar's size (Comma's AvatarSize): 24, 32, 40, 48, 56, 64 across.
#derive(Eq, Debug)
pub(all) enum AvatarSize {
  AvatarXs
  AvatarSm
  AvatarMd
  AvatarLg
  AvatarXl
  Avatar2xl
}

///|
/// Its side and its initials' role.
fn AvatarSize::looks(self : AvatarSize) -> (Double, TypeRole) {
  match self {
    AvatarXs => (24.0, type_mini)
    AvatarSm => (32.0, type_small)
    AvatarMd => (40.0, type_regular)
    AvatarLg => (48.0, type_large)
    AvatarXl => (56.0, type_title3)
    Avatar2xl => (64.0, type_title3)
  }
}

///|
/// A name's initials, as Comma's getInitials: the first letter of its first two words, upper case.
pub fn initials(name : String) -> String {
  let out = StringBuilder()
  let mut taken = 0
  let mut at_start = true
  for ch in name {
    if ch == ' ' {
      at_start = true
    } else if at_start && taken < 2 {
      out.write_string(ch.to_string().to_upper())
      taken += 1
      at_start = false
    } else {
      at_start = false
    }
  }
  out.to_string()
}

///|
/// Comma's avatar in `parent` for `name` (its initials), of `size`; `online`: its dot (Some(true) green, Some(false)
/// grey). Read out as an image named `name`. The node.
#callsite(autofill(loc))
pub fn avatar_node(
  parent : @view.View,
  name : () -> String,
  size? : AvatarSize = AvatarMd,
  online? : () -> Bool?,
  loc~ : SourceLoc,
) -> @view.View {
  let (side, role) = size.looks()
  let dot = if size is (AvatarXs | AvatarSm) { 6.0 } else { 10.0 }
  parent.box(made_for=loc, words_as_said=true, fn(a) {
    a
    .width(Is(Some(side)))
    .height(Is(Some(side)))
    .shrink(Is(0.0))
    .says(By(fn() { Some(@view.said(Image, label=name())) }))
    |> ignore
    // (the circle, its initials in its middle)
    a.box(fn(c) {
      c
      .over(Is(true))
      .radius(Is(side / 2.0))
      .lines_up(Is(Some(Middle)))
      .lies_along(Is(Middle))
      .ground(By(fn() { colors().avatar_bg }))
      .edge(By(fn() { (1.0, colors().avatar_profile_photo_border) }))
      |> ignore
      c.box(fn(w) {
        w
        .words(By(fn() { initials(name()) }), look=words_in(role, weight=weight_semibold))
        .ink(By(fn() { colors().text_tertiary }))
        |> ignore
      })
      |> ignore
    })
    |> ignore
    match online {
      Some(online) =>
        a.show(fn() { online() is Some(_) }, fn(o) {
          // (at its foot's end, ringed 2 in the page's ground past its own edge)
          o.over(Is(true)).lines_up(Is(Some(End))).lies_along(Is(End)) |> ignore
          o.box(fn(d) {
            d
            .width(Is(Some(dot + 4.0)))
            .height(Is(Some(dot + 4.0)))
            .margin(Is((0.0, 0.0, -2.0, -2.0)))
            .radius(Is(dot / 2.0 + 2.0))
            .ground(By(fn() {
              let c = colors()
              if online() == Some(true) {
                c.fg_success_primary
              } else {
                c.fg_quaternary
              }
            }))
            .edge(By(fn() { (2.0, colors().bg_primary) }))
            |> ignore
          })
          |> ignore
        })
      None => ()
    }
  })
}
