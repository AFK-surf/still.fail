// The pages pushed from Home, as far as these slices go: a chat (chat.mbt), the archive and settings (Parts.kt NavBar
// over nothing yet); the filter's menu (Sheet.kt MenuHost) and the workspaces' sheet (Workspaces.kt WorkspacesSheet, in
// Sheet.kt's frame).

///|
/// A phone menu's rows' ground menu_pad in from the panel's edge, rounded menu_row (Sheet.kt MenuHost MENU_PAD,
/// MENU_ROW); their words menu_words_in from the panel's edge.
let menu_pad : Double = 6.0

///|
let menu_row : Double = 14.0

///|
let menu_words_in : Double = 16.0

///|
/// A phone menu's panel (Sheet.kt MenuHost) at (`tx`, `ty`): 180 wide, the surface, the menu's shadow, its rows
/// menu_pad in, its corner concentric round theirs (concentricOut(MENU_ROW, MENU_PAD)).
fn phone_menu(c : @ui.Ctx, tx? : Double = 0.0, ty? : Double = 0.0, body : () -> Unit) -> Int {
  let t = @sf.theme()
  let menu = c.box(
    w=Px(180.0),
    tx~,
    ty~,
    pad=menu_pad,
    radius=@ui.concentric_out(menu_row, menu_pad),
    bg=t.p.card,
    shadow=@sf.menu_raised.sigma,
    shadow_y=@sf.menu_raised.dy,
    shadow_color=@sf.menu_raised.color,
    clip=true,
    body,
  )
  // (the menu: the surface of the look it comes in by: Ctx::surface)
  c.surface(menu)
  menu
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
      c.text(label, size=t.t.ui, color=t.p.text, wrap=false, line=21.0) |> ignore
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
