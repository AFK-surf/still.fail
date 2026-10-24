// Who is in a chat, small at its row's second line's end (ember web/src/RowPicture.tsx RowAside, Face;
// RowPicture.css.ts), as the chats' lists draw it with a finger and with a mouse alike: its agents' marks (a maker's
// once) and its people's faces, those that lead first.

///|
/// Who is in a chat at its row's second line's end (RowAside, `size` 16 with a mouse, 18 with a finger: Sidebar.tsx,
/// mobile/Home.tsx): its agents' marks (a maker's once, `size` less 4 in a column 16 wide, 4 apart; past three, +N)
/// and its people (round, each 3 over the one before with a pixel of the row's ground round it; who started it, of
/// more than one, ringed in ink a pixel past that, over the others), those that lead first, 6 apart; the people only
/// when they lead or someone other than the viewer is in it. `ground`: the row's ground, what is round each face.
pub fn row_aside(c : @ui.Ctx, src : Source, item : ChatItem, lead : String, ground : Int64) -> Unit {
  let groups = @sfbase.row_agent_groups(item)
  let people = item.people
  let with_people = people.length() > 0 && (lead == "people" || people.iter().any(fn(p) { !p.mine }))
  if groups.length() == 0 && !with_people {
    return
  }
  let finger = @sf.touch_system()
  let agents = fn() {
    let said = item.agents.map(fn(a) { a.text }).filter(fn(s) { s != "" })
    c.box(style=aside_agents, label=said.join(@sf.t("web-main.list.separator")), fn() {
      for k, g in groups {
        if k < aside_most {
          c.box(style=aside_agent, fn() {
            @sf.maker_mark(c, g.maker, g.runtime, if finger { touch_agent_mark } else { aside_agent_mark }) |> ignore
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
  let (face, after, round, ring, d) = if finger {
    (touch_face, touch_face_after, touch_face_ground, touch_face_ring, touch_face_d)
  } else {
    (mouse_face, mouse_face_after, mouse_face_ground, mouse_face_ring, mouse_face_d)
  }
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
  c.box(style=aside_row, fn() {
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
/// A face at a row's end: 16 across with a mouse, 18 with a finger; 3 over the one before it (RowPicture.css.ts aside
/// overlap(3)); its ground a pixel round it, who started it ringed 2 out; three shown at most.
let mouse_face_d : Double = 16.0

///|
let touch_face_d : Double = 18.0

///|
let face_over : Double = 3.0

///|
let face_ring_in : Double = 1.0

///|
let face_ring_out : Double = 2.0

///|
let aside_most : Int = 3

///|
/// An agent's mark at a row's end: 4 less than the faces (RowAside: size - 4).
let aside_agent_mark : Double = 12.0

///|
let touch_agent_mark : Double = 14.0

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
let aside_more : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
/// A face, round; one after the first takes 3 less (3 of it over the one before).
// kept across runs: a value (no field of it changes)
let mouse_face : @ui.Style = @ui.css("w=S4 h=S4")

///|
// kept across runs: a value (no field of it changes)
let mouse_face_after : @ui.Style = @ui.style(w=@sf.side_face_step, h=S4)

///|
// kept across runs: a value (no field of it changes)
let touch_face : @ui.Style = @ui.css("w=S4_5 h=S4_5")

///|
// kept across runs: a value (no field of it changes)
let touch_face_after : @ui.Style = @ui.style(w=@sf.touch_face_step, h=S4_5)

///|
/// The pixel after who started it (RowPicture.css.ts: marginRight 1).
// kept across runs: a value (no field of it changes)
let face_gap : @ui.Style = @ui.css("w=SPx h=S4")

///|
/// A pixel of the row's ground round a face (RowPicture.css.ts face: box-shadow 1px of --mark-around), its colour the
/// row's.
// kept across runs: a value (no field of it changes)
let mouse_face_ground : @ui.Style = @ui.css("w=S4_5 h=S4_5 radius=Full")

///|
// kept across runs: a value (no field of it changes)
let touch_face_ground : @ui.Style = @ui.css("w=S5 h=S5 radius=Full")

///|
/// Who started it ringed in ink, a pixel of ground between: a line 1 wide from 1 to 2 out (RowPicture.css.ts
/// face[data-starter]::after).
// kept across runs: a value (no field of it changes)
let mouse_face_ring : @ui.Style = @ui.css("w=S5 h=S5 radius=Full border=B1 border_color=Fg")

///|
// kept across runs: a value (no field of it changes)
let touch_face_ring : @ui.Style = @ui.style(w=@sf.touch_face_ring, h=@sf.touch_face_ring, radius=Full, border=B1, border_color=Fg)
