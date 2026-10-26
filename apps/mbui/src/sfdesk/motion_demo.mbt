// An opt-in motion study inside the real app. Every tile is chat_page itself, with the same Source and components.
// The flag is deliberately absent from release builds' environment; this is a review prototype, not a new default.
///|
let demo_spread : Ref[Bool] = Ref(false)
///|
let demo_chats : Array[ChatRef] = []
///|
let demo_selected : Ref[Int] = Ref(0)
///|
fn demo_open(c : @ui.Ctx, src : Source, w : Workspace, current : ChatRef) -> Unit {
  demo_chats.clear()
  demo_chats.push(current)
  match chats_of(src, w.id, "all").0 {
    Some(v) => for day in v.days {
      for row in day.items {
        if demo_chats.length() < 3 && row.session != current.session {
          demo_chats.push(@sfbase.chat_ref_of(row))
        }
      }
    }
    None => ()
  }
  demo_selected.val = 0
  demo_spread.val = true
  @motion.anim(c, "demo/spread", 0.0, global=true).animate(1.0, @motion.tween(@sf.move_state_ms, ease=Out))
}
///|
fn demo_chat_page(c : @ui.Ctx, src : Source, w : Workspace, current : ChatRef) -> Unit {
  let motion = @motion.anim(c, "demo/spread", 0.0, global=true)
  let p = motion.get()
  if demo_chats.length() == 0 || (!demo_spread.val && motion.over()) {
    chat_page(c, src, w, current)
    c.box(style=@ui.style(), left=24.0, top=62.0, fn() {
      if @sf.button(c, "摊开对话", key="demo/spread-open", tone=Primary, icon="layers") {
        demo_open(c, src, w, current)
      }
    }) |> ignore
    return
  }
  let width = c.width
  let height = c.height
  let gap = 16.0
  let tile = (width - gap * (demo_chats.length().to_double() + 1.0)) / demo_chats.length().to_double()
  let small = tile / width
  let scale = 1.0 + (small - 1.0) * p
  let top = (height - height * small) / 2.0
  c.box(style=@ui.css("w=Full h=Full bg=Sidebar clip=true"), fn() {
    // The selected page is last, so it expands over its neighbours.
    for pass in 0..<2 {
      for i, r in demo_chats {
        if (i == demo_selected.val) == (pass == 1) {
          let x = gap + i.to_double() * (tile + gap)
          let away = if i == demo_selected.val { 0.0 } else if i < demo_selected.val { -width } else { width }
          c.scope(94000 + i, fn() {
            let page = c.box(style=@ui.style(w=Fixed(width), h=Fixed(height), bg=Bg, clip=true), left=0.0, top=0.0, fn() {
              c.sized(width, height, fn() { chat_page(c, src, w, r) })
            })
            c.look(page, @ui.look(dx=away * (1.0-p) + x*p, dy=top*p, scale~, ox=0.0, oy=0.0))
            c.draw_only(page)
            if demo_spread.val {
              let id = c.id("demo/choose/\{i}")
              let hit = c.box(style=@ui.style(w=Fixed(tile), h=Fixed(height*small)), id~, left=x, top~, fn() { })
              c.semantics(hit, Button, id~, label="打开对话：" + r.title)
              if c.clicked(id) {
                demo_selected.val = i
                demo_spread.val = false
                open_page(Chat(r))
                motion.animate(0.0, @motion.tween(@sf.move_state_ms, ease=Out))
              }
              let caption = c.box(style=@ui.style(w=Fixed(tile), align=ACenter), left=x, top=top+height*small+gap, fn() {
                c.text(r.title, style=@sf.secondary) |> ignore
              })
              c.look(caption, @ui.look(alpha=p))
            }
          })
        }
      }
    }
  }) |> ignore
}
