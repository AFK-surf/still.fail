// Who is in a chat, small at its row's second line's end (ember web/src/RowPicture.tsx RowAside, Face;
// RowPicture.css.ts), as the chats' lists draw it with a finger and with a mouse alike: its agents' marks (a maker's
// once) and its people's faces, those that lead first.

///|
/// Whether a row shows who is in it at its end (row_aside: its agents, the people where they are not all the viewer).
pub fn row_aside_shows(item : ChatItem, lead : String) -> Bool {
  @sfbase.row_agent_groups(item).length() > 0 || row_with_people(item, lead)
}

///|
fn row_with_people(item : ChatItem, lead : String) -> Bool {
  let people = item.people
  people.length() > 0 && (lead == "people" || people.iter().any(fn(p) { !p.mine }))
}

///|
/// How wide the last of what stands in a row's foot's end corner is (row_aside: a face, or an agent's mark), whose
/// middle the marks at its first line's end stand over (@sf.list_row's `corner_end`).
pub fn row_aside_end_w(item : ChatItem, lead : String) -> Double {
  let agents = @sfbase.row_agent_groups(item).length() > 0
  let faces = row_with_people(item, lead)
  let faces_last = faces && (lead != "people" || !agents)
  if faces_last {
    @sf.theme().chat_list.face_d
  } else {
    aside_agent_w
  }
}

///|
/// How wide what row_aside shows is, by its parts' sizes (the theme's chats' list): the room a row keeps for it where
/// it stands in the row's corner, out of the line's flow (list_row `corner`).
pub fn row_aside_w(c : @ui.Ctx, item : ChatItem, lead : String) -> Double {
  let l = @sf.theme().chat_list
  let groups = @sfbase.row_agent_groups(item)
  let people = item.people
  let more_w = fn(n : Int) { @ui.text_advance("+\{n}", size=c.sp(c.text_size(Meta).0)) }
  let parts : Array[Double] = []
  if groups.length() > 0 {
    let shown = if groups.length() > aside_most { aside_most } else { groups.length() }
    let mut w = aside_in + shown.to_double() * aside_agent_w + (shown - 1).to_double() * aside_agent_gap
    if groups.length() > aside_most {
      w = w + aside_agent_gap + more_w(groups.length() - aside_most)
    }
    parts.push(w)
  }
  if row_with_people(item, lead) {
    let shown = if people.length() > aside_most { aside_most } else { people.length() }
    // (each after the first over the one before it by face_over)
    let mut w = aside_in + l.face_d + (shown - 1).to_double() * (l.face_d - face_over)
    if people.length() > 1 && people[:shown].iter().any(fn(p) { p.id == item.creator }) {
      w = w + face_gap_w
    }
    if people.length() > shown {
      w = w + more_w(people.length() - shown)
    }
    parts.push(w)
  }
  parts.fold(init=0.0, fn(a, b) { a + b }) + (parts.length() - 1).to_double() * aside_parts_gap
}

///|
/// Who is in a chat at its row's second line's end (RowAside, `size` 16 with a mouse, 18 with a finger: Sidebar.tsx,
/// mobile/Home.tsx): its agents' marks (a maker's once, `size` less 4 in a column 16 wide, 4 apart; past three, +N)
/// and its people (round, each 3 over the one before with a pixel of the row's ground round it; who started it, of
/// more than one, ringed in ink a pixel past that, over the others), those that lead first, 6 apart; the people only
/// when they lead or someone other than the viewer is in it. `ground`: the row's ground, what is round each face
/// (`ground_by`: worked out as it is painted, @ui.Ctx::bg_by, in its place);
/// `lift`: how far over the line's middle they stand (in the row's foot corner, concentric with it: chat_row's).
pub fn row_aside(
  c : @ui.Ctx,
  src : Source,
  item : ChatItem,
  lead : String,
  ground : Int64,
  ground_by? : () -> Int64,
) -> Unit {
  let groups = @sfbase.row_agent_groups(item)
  let people = item.people
  let with_people = row_with_people(item, lead)
  if groups.length() == 0 && !with_people {
    return
  }
  // (its sizes the screen's: the theme's chats' list)
  let l = @sf.theme().chat_list
  // (who they are over them while they are pointed at: RowAside's tips)
  let key = "row-aside/" + item.station + "/" + item.id
  let agents = fn() {
    let said = item.agents.map(fn(a) { a.text }).filter(fn(s) { s != "" }).join(@sf.t("web-main.list.separator"))
    let id = c.id(key + "/agents")
    c.box(style=aside_agents, label=said, id~, taps=false, points=true, fn() {
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
    @sf.tip(c, key + "/agents-tip", id, said)
  }
  let (face, after, round, ring, d) = (l.face, l.face_after, l.face_ground, l.face_ring, l.face_d)
  let round = round.then(@ui.style(bg=Data(ground)))
  let faces = fn() {
    let shown = if people.length() > aside_most { people[:aside_most].to_array() } else { people }
    let id = c.id(key + "/faces")
    c.box(style=aside_faces, label=item.people_text, id~, taps=false, points=true, fn() {
      for i, p in shown {
        let starter = people.length() > 1 && p.id == item.creator
        let slot = c.box(style=if i == 0 { face } else { after }, fn() {
          c.box(style=face, tx=if i == 0 { 0.0 } else { -face_over }, fn() {
            c.layer(fn() {
              let r = c.box(style=round, tx=-face_ring_in, ty=-face_ring_in, fn() {  })
              match ground_by {
                Some(f) => c.bg_by(r, f)
                None => ()
              }
            })
            |> ignore
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
    @sf.tip(c, key + "/faces-tip", id, item.people_text)
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
/// A face at a row's end (its size the theme's chats' list): 3 over the one before it (RowPicture.css.ts aside
/// overlap(3)); its ground a pixel round it, who started it ringed 2 out; three shown at most.
let face_over : Double = 3.0

///|
/// What stands at a row's end, measured as its styles lay it (aside_row, aside_agents, aside_agent, aside_faces,
/// face_gap): 2 in, an agent 16 and 4 apart, the agents and the people 6 apart, a pixel after who started it.
let aside_in : Double = 2.0

///|
let aside_agent_w : Double = 16.0

///|
let aside_agent_gap : Double = 4.0

///|
let aside_parts_gap : Double = 6.0

///|
let face_gap_w : Double = 1.0

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

