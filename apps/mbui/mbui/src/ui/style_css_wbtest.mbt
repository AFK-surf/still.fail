///|
/// css(…) is the same Style as style(…) said with the same items.
fn css_same(text : String, want : Style) -> Unit raise {
  if css(text) != want {
    fail("css(\"\{text}\") is not the style(…) it says")
  }
}

///|
test "css: plain items, row and clip alone" {
  css_same("", style())
  css_same(
    "row h=S7 px=S2 gap=S1_25 radius=Lg align=ACenter",
    style(row=true, h=S7, px=S2, gap=S1_25, radius=Lg, align=ACenter),
  )
  css_same("  row   clip\nw=Full\t", style(row=true, clip=true, w=Full))
  css_same("row=false clip=false", style(row=false, clip=false))
}

///|
test "css: every property, a token read by its property's type" {
  // Full a Len's in w=, a Radius's in radius=; Sm a Radius's and a Shadow's
  css_same(
    "w=Full h=Hug min_w=S0 max_w=S96 min_h=SPx max_h=S0_5 p=S1 px=S1_5 py=S2_5 pl=S3_5 pr=S4_5 pt=S5 pb=S6 " +
    "m=S8 mx=S9 my=S10 ml=S11 mr=S12 mt=S14 mb=S16 gap=S20 align=AStretch justify=JBetween bg=Card " +
    "radius=Full border=B0_5 border_color=Border shadow=Sm clip opacity=O35",
    style(
      w=Full,
      h=Hug,
      min_w=S0,
      max_w=S96,
      min_h=SPx,
      max_h=S0_5,
      p=S1,
      px=S1_5,
      py=S2_5,
      pl=S3_5,
      pr=S4_5,
      pt=S5,
      pb=S6,
      m=S8,
      mx=S9,
      my=S10,
      ml=S11,
      mr=S12,
      mt=S14,
      mb=S16,
      gap=S20,
      align=AStretch,
      justify=JBetween,
      bg=Card,
      radius=Full,
      border=B0_5,
      border_color=Border,
      shadow=Sm,
      clip=true,
      opacity=O35,
    ),
  )
  css_same(
    "align=AStart justify=JStart radius=Sm shadow=NoShadow border=B8",
    style(align=AStart, justify=JStart, radius=Sm, shadow=NoShadow, border=B8),
  )
  css_same(
    "align=AEnd justify=JEnd radius=Inner shadow=Xl border=B0",
    style(align=AEnd, justify=JEnd, radius=Inner, shadow=Xl, border=B0),
  )
  css_same(
    "align=ACenter justify=JCenter radius=Around w=S72 h=S80",
    style(align=ACenter, justify=JCenter, radius=Around, w=S72, h=S80),
  )
}

///|
test "css: constructors with numbers, the same Doubles as the literals" {
  css_same(
    "w=Grow(1.0) h=Fixed(240) min_w=Pct(33.333) max_w=Fixed(0.1) gap=Exact(1.15) radius=Exact(3.5)",
    style(
      w=Grow(1.0),
      h=Fixed(240.0),
      min_w=Pct(33.333),
      max_w=Fixed(0.1),
      gap=Exact(1.15),
      radius=Exact(3.5),
    ),
  )
  css_same(
    "ml=Exact(-4.0) mt=Exact(-0.5) w=Fixed(1_000.25) h=Fixed(2.5e3) opacity=Exact(0.07)",
    style(
      ml=Exact(-4.0),
      mt=Exact(-0.5),
      w=Fixed(1000.25),
      h=Fixed(2500.0),
      opacity=Exact(0.07),
    ),
  )
  css_same(
    "shadow=Cast(12.5, 4, 0x00000033) bg=A(Fg,O5) border_color=Over(Card, A(Accent, O70))",
    style(
      shadow=Cast(12.5, 4.0, 0x00000033L),
      bg=A(Fg, O5),
      border_color=Over(Card, A(Accent, O70)),
    ),
  )
  css_same(
    "bg=Exact(0x24272BFF) border_color=Data(4294967295)",
    style(bg=Exact(0x24272BFFL), border_color=Data(4294967295L)),
  )
  css_same(
    "bg=Over(Over(Faint, Hover), A(Bg, Exact(0.125)))",
    style(bg=Over(Over(Faint, Hover), A(Bg, Exact(0.125)))),
  )
}

///|
test "css: state blocks" {
  css_same(
    "row w=Full narrow{px=S4} dark{bg=Raised} selected{bg=Selected} hovered{bg=Hover radius=Lg} " +
    "focused{border=B2 border_color=Focus} pressed{bg=Over(Card,A(Fg,O5))} disabled{opacity=O50 row=false}",
    style(
      row=true,
      w=Full,
      narrow=patch(px=S4),
      dark=patch(bg=Raised),
      selected=patch(bg=Selected),
      hovered=patch(bg=Hover, radius=Lg),
      focused=patch(border=B2, border_color=Focus),
      pressed=patch(bg=Over(Card, A(Fg, O5))),
      disabled=patch(opacity=O50, row=false),
    ),
  )
  css_same("hovered{} pressed{ clip }", style(hovered=patch(), pressed=patch(clip=true)))
}

///|
test "panic css: a property it does not know" {
  css("wdth=S4") |> ignore
}

///|
test "panic css: a token not of the property's type" {
  css("px=Full") |> ignore
}

///|
test "panic css: a block in a block" {
  css("hovered{pressed{bg=Hover}}") |> ignore
}

///|
test "panic css: a block not closed" {
  css("hovered{bg=Hover") |> ignore
}

///|
test "panic css: items not apart" {
  css("bg=A(Fg,O5)px=S2") |> ignore
}

///|
test "panic css: a number not read exactly" {
  css("w=Fixed(0.12345678901234567)") |> ignore
}
