// Ready styles (docs/style.md, "kit's recipes"): a card, a list's row, a section's header, a button, a field, a badge,
// a panel, and the words of a row, made of the theme's tokens alone. An app's theme (Ctx::set_theme) changes the
// tokens' values, and these are its look; what does not fit the scale goes in the app's own styles or token file,
// not here. A variant is a parameter (its default the usual one), a pair of them that looks otherwise a `match`.

///|
pub(all) enum CardTone {
  /// on the page, a ground of its own
  Plain
  /// lifted over the page, with a shadow
  Lifted
} derive(Eq, Show, Debug)

///|
/// A card: a block of its own on the page, rounded, padded so that what lies in its corners is concentric with it
/// (rows in it `Inner`: list_row).
pub fn card(tone? : CardTone = Plain) -> @ui.Style {
  let base = @ui.style(w=Full, p=S5, radius=Xl3, bg=Card, clip=true)
  match tone {
    Plain => base
    Lifted => base.then(@ui.style(bg=Raised, shadow=Md))
  }
}

///|
/// A card that holds rows (list_row): padded little, the rows' corners its own less that (`Inner`).
pub fn list_card() -> @ui.Style {
  card().then(@ui.style(p=S2, gap=S0_5))
}

///|
pub(all) enum Density {
  Comfy
  Compact
} derive(Eq, Show, Debug)

///|
/// A row of a list: what it shows in a line, a tint while pointed at and held, chosen in its colour; its corner
/// concentric with the card that holds it (`Inner`).
pub fn list_row(density? : Density = Comfy) -> @ui.Style {
  @ui.style(
    row=true,
    w=Full,
    align=ACenter,
    gap=S3,
    px=S3,
    py=match density {
      Comfy => S3
      Compact => S2
    },
    radius=Inner,
    hovered=@ui.patch(bg=Hover),
    pressed=@ui.patch(bg=A(Fg, O10)),
    selected=@ui.patch(bg=Selected),
    disabled=@ui.patch(opacity=O40),
  )
}

///|
pub(all) enum Indent {
  /// in line with the page's words
  Page
  /// in line with the words in a card's rows
  Inset
} derive(Eq, Show, Debug)

///|
/// What heads a section of a page (its words: section_title).
pub fn section_header(indent? : Indent = Page) -> @ui.Style {
  @ui.style(
    w=Full,
    pt=S6,
    pb=S2,
    px=match indent {
      Page => S0
      Inset => S5
    },
  )
}

///|
pub(all) enum ButtonSize {
  Sm
  Md
  Lg
} derive(Eq, Show, Debug)

///|
/// A button (button.mbt's Variant its tone): a pill of its size, its ground by its tone, tinted pointed at and held, faded when disabled; its words
/// button_text. A small ghost button has no padding at its sides (it sits in line with words).
pub fn button_style(size? : ButtonSize = Md, tone? : Variant = Solid) -> @ui.Style {
  let base = @ui.style(
    row=true,
    align=ACenter,
    justify=JCenter,
    gap=S2,
    radius=Full,
    disabled=@ui.patch(opacity=O40),
  )
  let sized = match size {
    Sm => @ui.style(h=S7, px=S3)
    Md => @ui.style(h=S9, px=S4)
    Lg => @ui.style(h=S11, px=S6)
  }
  let toned = match tone {
    Solid =>
      @ui.style(
        bg=Primary,
        hovered=@ui.patch(bg=Over(Primary, A(Bg, O10))),
        pressed=@ui.patch(bg=Over(Primary, A(Bg, O20))),
      )
    Soft =>
      @ui.style(
        bg=Faint,
        hovered=@ui.patch(bg=Over(Faint, Hover)),
        pressed=@ui.patch(bg=Over(Over(Faint, Hover), Hover)),
      )
    Ghost =>
      @ui.style(bg=Clear, hovered=@ui.patch(bg=Hover), pressed=@ui.patch(bg=A(Fg, O10)))
    Outline =>
      @ui.style(
        bg=Clear,
        border=B1,
        border_color=Border,
        hovered=@ui.patch(bg=Hover),
        pressed=@ui.patch(bg=A(Fg, O10)),
      )
    Danger =>
      @ui.style(
        bg=Danger,
        hovered=@ui.patch(bg=Over(Danger, A(Bg, O10))),
        pressed=@ui.patch(bg=Over(Danger, A(Bg, O20))),
      )
  }
  let compound = match (size, tone) {
    (Sm, Ghost) => @ui.style(px=S0)
    _ => @ui.style()
  }
  base.then(sized).then(toned).then(compound)
}

///|
/// A button's words, by its size and tone.
pub fn button_text(size? : ButtonSize = Md, tone? : Variant = Solid) -> @ui.TextStyle {
  @ui.text_style(
    size=match size {
      Sm => Xs
      Md | Lg => Sm
    },
    weight=Medium,
    wrap=false,
    color=match tone {
      Solid => OnPrimary
      Soft | Outline | Ghost => Fg
      Danger => OnDanger
    },
  )
}

///|
pub(all) enum FieldSize {
  Sm
  Md
} derive(Eq, Show, Debug)

///|
/// A field's frame: an edge in the theme's border, its colour pointed at and focused.
pub fn field(size? : FieldSize = Md) -> @ui.Style {
  @ui.style(
    row=true,
    w=Full,
    h=match size {
      Sm => S8
      Md => S9
    },
    px=S3,
    align=ACenter,
    gap=S2,
    radius=Xl,
    bg=Bg,
    border=B1,
    border_color=Border,
    hovered=@ui.patch(border_color=Muted),
    focused=@ui.patch(border_color=Focus),
    disabled=@ui.patch(opacity=O40),
  )
}

///|
pub(all) enum BadgeTone {
  Neutral
  Accent
  Positive
  Danger
} derive(Eq, Show, Debug)

///|
/// A badge: a small pill (its words badge_text).
pub fn badge(tone? : BadgeTone = Neutral) -> @ui.Style {
  @ui.style(
    row=true,
    align=ACenter,
    px=S2,
    py=S0_5,
    radius=Full,
    bg=match tone {
      Neutral => Neutral
      Accent => AccentBg
      Positive => A(Positive, O10)
      Danger => DangerBg
    },
  )
}

///|
/// A badge's words.
pub fn badge_text(tone? : BadgeTone = Neutral) -> @ui.TextStyle {
  @ui.text_style(
    size=Xs,
    weight=Medium,
    wrap=false,
    color=match tone {
      Neutral => Muted
      Accent => AccentText
      Positive => Positive
      Danger => Danger
    },
  )
}

///|
/// What a menu, a popover lies on: over the page, an edge, a shadow; padded little, its items' corners `Inner`.
pub fn panel() -> @ui.Style {
  @ui.style(
    p=S1_5,
    gap=S0_5,
    radius=Xl2,
    bg=Surface,
    border=B1,
    border_color=Line,
    shadow=Lg,
    clip=true,
  )
}

///|
pub(all) enum RowTone {
  Normal
  /// what failed, what cannot be undone
  Bad
} derive(Eq, Show, Debug)

///|
/// A row's title.
pub fn row_title(tone? : RowTone = Normal) -> @ui.TextStyle {
  @ui.text_style(
    size=Base,
    weight=Medium,
    color=match tone {
      Normal => Fg
      Bad => Danger
    },
  )
}

///|
/// What is said under a row's title.
pub fn row_sub(tone? : RowTone = Normal) -> @ui.TextStyle {
  @ui.text_style(
    size=Sm,
    color=match tone {
      Normal => Muted
      Bad => Danger
    },
  )
}

///|
/// A row's value, at its end.
pub fn row_value(tone? : RowTone = Normal) -> @ui.TextStyle {
  @ui.text_style(
    size=Sm,
    wrap=false,
    color=match tone {
      Normal => Subtle
      Bad => Danger
    },
  )
}

///|
/// A section's heading's words (section_header).
pub fn section_title() -> @ui.TextStyle {
  @ui.text_style(size=Xs, weight=Semibold, color=Muted, wrap=false)
}
