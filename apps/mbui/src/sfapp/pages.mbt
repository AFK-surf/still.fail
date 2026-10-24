// The pages pushed from Home, as far as these slices go: a chat (chat.mbt), the archive and settings (Parts.kt NavBar
// over nothing yet); the filter's menu (Sheet.kt MenuHost) and the workspaces' sheet (Workspaces.kt WorkspacesSheet, in
// Sheet.kt's frame).

///|
/// A page's compact bar (Parts.kt NavBar): back to the chats, in the accent; its title in the middle.
fn nav_bar(c : @ui.Ctx, title : String) -> Unit {
  if @sf.nav_bar(c, "nav-back", tr("android-misc.bar.place.chats"), title, top=status_top()) {
    app.nav.pop() |> ignore
  }
}

///|
/// A list card on a sheet (Parts.kt RowsCard): its rows list_pad in, its corner concentric round theirs; its ground the
/// caller's (the workspace in use: the chips' grey).
// kept across runs: a value (no field of it changes)
let chip_list_card : @ui.Style = @ui.style(w=Full, p=S2, radius=@sf.list_card_radius, clip=true)

///|
/// A phone menu's rows' ground menu_pad in from the panel's edge, rounded menu_row (Sheet.kt MenuHost MENU_PAD,
/// MENU_ROW); their words menu_words_in from the panel's edge.
let menu_pad : Double = 6.0

///|
let menu_row : Double = 14.0

///|
let menu_words_in : Double = 16.0

///|
/// A phone menu's height of `n` rows of 45 (MenuHost's menuHeight: 45 a row, its padding over and under).
fn menu_height(n : Int) -> Double {
  45.0 * n.to_double() + menu_pad * 2.0
}

///|
/// A phone menu's panel (Sheet.kt MenuHost) at (`tx`, `ty`): 180 wide, the surface, the menu's shadow, its rows
/// menu_pad in, its corner concentric round theirs (concentricOut(MENU_ROW, MENU_PAD)).
fn phone_menu(c : @ui.Ctx, tx? : Double = 0.0, ty? : Double = 0.0, body : () -> Unit) -> Int {
  let t = @sf.theme()
  c.box(
    w=Px(180.0),
    tx~,
    ty~,
    pad=menu_pad,
    radius=@sf.surface_corner(menu_pad, menu_row),
    bg=t.p.card,
    shadow=@sf.menu_raised.sigma,
    shadow_y=@sf.menu_raised.dy,
    shadow_color=@sf.menu_raised.color,
    clip=true,
    body,
  )
}

///|
/// A phone menu's row (MenuHost): `label` menu_words_in from the panel's edge, 12 over and under, `icon` (16) at its
/// end ("": its room kept); its ground rounded menu_row, the words' colour at 6% times `lit` (pressed, or the finger
/// or the keyboard on it).
fn phone_menu_row(c : @ui.Ctx, label : String, icon~ : String, lit~ : Double, id? : Int = 0) -> Int {
  let t = @sf.theme()
  c.box(
    dir=Row,
    w=Fill(1.0),
    padx=menu_words_in - menu_pad,
    pady=12.0,
    align=ACenter,
    justify=JBetween,
    radius=menu_row,
    bg=if lit > 0.0 { @sf.alpha(t.p.text, 0.06 * lit) } else { 0L },
    id~,
    fn() {
      c.text(label, size=15.0, color=t.p.text, wrap=false, line=21.0) |> ignore
      if icon != "" {
        @sf.icon(c, icon, size=16.0, color=t.p.text) |> ignore
      } else {
        c.box(w=Px(16.0), h=Px(16.0), fn() {  }) |> ignore
      }
    },
  )
}

///|
/// A menu's panel in MenuHost's look, for mbui's dropdown menu.
fn menu_panel_look(c : @ui.Ctx, _min_w : Double, body : () -> Unit) -> Unit {
  phone_menu(c, body) |> ignore
}

///|
/// A menu's row in MenuHost's look, `icon` at its end: rippled where a finger presses it (Sheet.kt MenuHost:
/// clip(Smooth(MENU_ROW)).clickable), lit while the keyboard's focus shows on it.
fn menu_row_look(c : @ui.Ctx, s : @kit.MenuItemState, icon : String) -> Unit {
  phone_menu_row(c, s.entry.label, icon~, lit=if s.lit && c.focus_shown(s.id) { 1.0 } else { 0.0 }) |> ignore
  if !s.entry.disabled {
    @motion.ripple(c, s.id, menu_row)
  }
}

///|
fn sheet_label(c : @ui.Ctx, label : String) -> Unit {
  let t = @sf.theme()
  c.box(pl=20.0, pr=20.0, pt=6.0, pb=2.0, fn() {
    c.text(label, size=13.0, color=t.p.muted, wrap=false) |> ignore
  })
  |> ignore
}

///|
/// A row of a picking sheet (Controls.kt PickRow): what, a line under it, a check on the chosen one; before it an
/// icon. True on the frame after it was tapped.
fn pick_row(
  c : @ui.Ctx,
  key : String,
  label : String,
  sub : String,
  checked : Bool,
  icon : String,
  on_card? : Bool = false,
) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  // on a list card (Parts.kt PickRow, LocalOnCard): its words card_pad from the card's edge, the card's list_pad in
  // already; on a sheet, 12 in and 8 more
  c.box(w=Fill(1.0), pl=if on_card { 0.0 } else { 12.0 }, pr=if on_card { 0.0 } else { 12.0 }, fn() {
    c.box(
      dir=Row,
      w=Fill(1.0),
      padx=if on_card { @sf.card_pad - @sf.list_pad } else { 8.0 },
      pady=12.0,
      gap=12.0,
      align=ACenter,
      id~,
      fn() {
        if icon != "" {
          @sf.icon(c, icon, size=20.0, color=t.p.text) |> ignore
        }
        c.box(w=Fill(1.0), fn() {
          c.text(label, size=15.0, color=t.p.text, wrap=false, line=21.0) |> ignore
          if sub != "" {
            c.text(sub, size=12.0, color=t.p.muted, wrap=false, line=17.0) |> ignore
          }
        })
        |> ignore
        if checked {
          @sf.icon(c, "check", size=14.0, color=t.p.accent) |> ignore
        }
        // Workspaces.kt: clip(Smooth(LIST_ROW_CORNER)).clickable
        @motion.ripple(c, id, @sf.row_corner)
      },
    )
    |> ignore
  })
  |> ignore
  c.clicked(id)
}

