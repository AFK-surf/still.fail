// An agent's mark (ember web/src/ui.tsx AgentMark, ui.css.ts agentMark): its model's maker on a tile of the neutral
// ground, its corner .3 of its side; where it stands a mark at the corner, the chat list's own (chat_mark.mbt): yellow
// spokes stepping round at work, blue when it waits on a person, red when it failed, ringed in the ground it is on.

///|
/// `maker`'s mark (of `runtime`) on its tile `side` across: 14 (an agent's line in the chat's info), 16 (a line of a
/// history's details), 20 (the chat's bar) or 28 (an agent's card); `badge` (run, block, failed, or none) at its
/// corner, said as `said` to a screen reader, ringed in `ground`, what the mark stands on (the page's; a small
/// panel's in one). Its tile's corner .3 of its side, or `corner` where it stands in a corner it is concentric with
/// (an agent's card's top left, on its words' line: the ladder's small block's 10, all four alike). When `joined`,
/// its enclosing tile paints the ground and hover: the mark adds no round ground over the straight seam.
pub fn agent_mark(
  c : @ui.Ctx,
  maker : String,
  runtime : String,
  badge : String,
  side? : Double = 20.0,
  said? : String = "",
  ground? : Int64 = @sf.theme().p.bg,
  corner? : @ui.Radius,
  joined? : Bool = false,
) -> Unit {
  let round = match corner {
    Some(k) => k
    None => @sf.agent_mark_corner(side)
  }
  let tile = (if joined { agent_contents } else { agent_tile }).then(@ui.style(w=Fixed(side), h=Fixed(side), radius=round))
  c.box(style=tile, label=said, fn() {
    @sf.maker_mark(c, maker, runtime, (side * agent_logo_of).round()) |> ignore
    agent_badge(c, badge, side, ground)
  })
  |> ignore
}

///|
/// The badge at a mark's corner `side` across, as a 20 one's has it (ui.css.ts agentMark ::after, ::before) and no
/// larger on a larger one: a dot 12 across ringed 2 in `ground`, 3 past the corner, blue waiting on a person (block)
/// and red failed; the spokes 10, 2 past it. On a smaller mark all of it as much smaller, its maker still seen past it
/// (a badge 12 across covered a 14 one's whole maker but a sliver). A phone's bar draws this one too.
pub fn agent_badge(c : @ui.Ctx, badge : String, side : Double, ground : Int64) -> Unit {
  let k = dmin(side / agent_badge_full, 1.0)
  match badge {
    "block" | "failed" => {
      let d = agent_badge_d * k
      let at = side - d + agent_badge_past * k
      let ring = @ui.style(w=Fixed(d), h=Fixed(d), p=@sf.room_of(agent_badge_ring * k)).then(agent_badge_round)
      c.layer(fn() {
        c.box(style=ring.then(@ui.style(bg=Data(ground))), tx=at, ty=at, fn() {
          c.box(style=if badge == "block" { agent_badge_blue } else { agent_badge_red }, fn() {  }) |> ignore
        })
        |> ignore
      })
      |> ignore
    }
    "run" => {
      let d = agent_spokes * k
      let at = side - d + agent_spokes_past * k
      c.layer(fn() {
        c.box(style=@ui.style(w=Fixed(d), h=Fixed(d)), tx=at, ty=at, fn() {
          @sf.spokes(c, d, @sf.mark_yellow) |> ignore
        })
        |> ignore
      })
      |> ignore
    }
    _ => ()
  }
}

///|
/// How large the maker's mark is on its tile (ui.tsx: .62 of it, rounded).
let agent_logo_of : Double = 0.62

///|
/// The side a badge is drawn whole at (the chat's bar's mark: the web's, made for it), smaller marks' badges as much
/// smaller: the red one 12 across, its ring 2, 3 past the corner; the spokes 10, 2 past it.
let agent_badge_full : Double = 20.0

///|
let agent_badge_d : Double = 12.0

///|
let agent_badge_ring : Double = 2.0

///|
let agent_badge_past : Double = 3.0

///|
let agent_spokes : Double = 10.0

///|
let agent_spokes_past : Double = 2.0

///|
/// A tile of the neutral ground, what is on it in its middle (its side and corner the mark's).
// kept across runs: a value (no field of it changes)
let agent_tile : @ui.Style = @ui.css("bg=Neutral align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let agent_contents : @ui.Style = @ui.css("align=ACenter justify=JCenter")

///|
/// The badge round; red within its ring.
// kept across runs: a value (no field of it changes)
let agent_badge_round : @ui.Style = @ui.css("radius=Full")

///|
// kept across runs: a value (no field of it changes)
let agent_badge_red : @ui.Style = @ui.style(w=Full, h=Full, radius=Full, bg=@sf.mark_red)

///|
// kept across runs: a value (no field of it changes)
let agent_badge_blue : @ui.Style = @ui.style(w=Full, h=Full, radius=Full, bg=@sf.mark_blue)
