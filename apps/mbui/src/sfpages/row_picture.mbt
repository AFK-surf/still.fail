// Who is in a chat, small at its row's second line's end (ember web/src/RowPicture.tsx RowAside, Face;
// RowPicture.css.ts), as the chats' lists draw it with a finger and with a mouse alike: its agents' marks (a maker's
// once) and its people's faces, those that lead first.

///|
/// Who is in a chat at its row's second line's end (RowAside, `size` 16 with a mouse, 18 with a finger: Sidebar.tsx,
/// mobile/Home.tsx): its agents' marks (a maker's once, `size` less 4 in a column 16 wide, 4 apart; past three, +N)
/// and its people (round, each 3 over the one before with a pixel of the row's ground round it; who started it, of
/// more than one, ringed in ink a pixel past that, over the others), those that lead first, 6 apart; the people only
/// when they lead or someone other than the viewer is in it. `ground`: the row's ground, what is round each face;
/// `lift`: how far over the line's middle they stand (in the row's foot corner, concentric with it: chat_row's).
pub fn row_aside(
  c : @ui.Ctx,
  src : Source,
  item : ChatItem,
  lead : String,
  ground : Int64,
  lift? : Double = 0.0,
) -> Unit {
  let groups = @sfbase.row_agent_groups(item)
  let people = item.people
  let with_people = people.length() > 0 && (lead == "people" || people.iter().any(fn(p) { !p.mine }))
  if groups.length() == 0 && !with_people {
    return
  }
  // (its sizes the screen's: the theme's chats' list)
  let l = @sf.theme().chat_list
  let agents = fn() {
    let said = item.agents.map(fn(a) { a.text }).filter(fn(s) { s != "" })
    c.box(style=aside_agents, label=said.join(@sf.t("web-main.list.separator")), fn() {
      for k, g in groups {
        if k < aside_most {
          c.box(style=aside_agent, fn() {
            @sf.maker_mark(c, g.maker, g.runtime, l.agent_mark) |> ignore
          })
          |> ignore
        }
      }
      if groups.length() > aside_most {
        c.text("+\{groups.length() - aside_most}", style=aside_more) |> ignore
      }
    })
    |> ignore
  }
  let (face, after, round, ring, d) = (l.face, l.face_after, l.face_ground, l.face_ring, l.face_d)
  let round = round.then(@ui.style(bg=Data(ground)))
  let faces = fn() {
    let shown = if people.length() > aside_most { people[:aside_most].to_array() } else { people }
    c.box(style=aside_faces, label=item.people_text, fn() {
      for i, p in shown {
        let starter = people.length() > 1 && p.id == item.creator
        let slot = c.box(style=if i == 0 { face } else { after }, fn() {
          c.box(style=face, tx=if i == 0 { 0.0 } else { -face_over }, fn() {
            c.layer(fn() { c.box(style=round, tx=-face_ring_in, ty=-face_ring_in, fn() {  }) |> ignore }) |> ignore
            let picture = if p.picture != "" { (src.picture)(p.picture, c.page_stint()) } else { "" }
            @sf.avatar(c, if p.email != "" { p.email } else { p.id }, p.name, picture, d)
            if starter {
              c.layer(fn() { c.box(style=ring, tx=-face_ring_out, ty=-face_ring_out, fn() {  }) |> ignore })
              |> ignore
            }
          })
          |> ignore
        })
        // who started it over the rest, a pixel more after it
        if starter {
          c.put_over(slot)
          c.box(style=face_gap, fn() {  }) |> ignore
        }
      }
      if people.length() > shown.length() {
        c.text("+\{people.length() - shown.length()}", style=aside_more) |> ignore
      }
    })
    |> ignore
  }
  c.box(style=aside_row, ty=-lift, fn() {
    if lead == "people" {
      if with_people {
        faces()
      }
      if groups.length() > 0 {
        agents()
      }
    } else {
      if groups.length() > 0 {
        agents()
      }
      if with_people {
        faces()
      }
    }
  })
  |> ignore
}

///|
/// A face at a row's end (its size the theme's chats' list): 3 over the one before it (RowPicture.css.ts aside
/// overlap(3)); its ground a pixel round it, who started it ringed 2 out; three shown at most.
let face_over : Double = 3.0

///|
let face_ring_in : Double = 1.0

///|
let face_ring_out : Double = 2.0

///|
let aside_most : Int = 3

///|
/// What stands at a row's second line's end (RowPicture.css.ts aside): the agents and the people 6 apart, each 2 in.
// kept across runs: a value (no field of it changes)
let aside_row : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let aside_agents : @ui.Style = @ui.css("row pl=S0_5 gap=S1 align=ACenter")

///|
/// An agent's mark in a column 16 wide and high (RowPicture.css.ts asideAgent).
// kept across runs: a value (no field of it changes)
let aside_agent : @ui.Style = @ui.css("w=S4 h=S4 align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let aside_faces : @ui.Style = @ui.css("row pl=S0_5 align=ACenter")

///|
/// How many more than are shown (RowPicture.css.ts asideMore): 12, muted.
// kept across runs: a value (no field of it changes)
let aside_more : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
/// The pixel after who started it (RowPicture.css.ts: marginRight 1).
// kept across runs: a value (no field of it changes)
let face_gap : @ui.Style = @ui.css("w=SPx h=S4")

