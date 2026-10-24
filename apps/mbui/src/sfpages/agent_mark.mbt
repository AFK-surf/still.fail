// An agent's mark (ember web/src/ui.tsx AgentMark, ui.css.ts agentMark): its model's maker on a tile of the neutral
// ground, its corner .3 of its side; where it stands a mark at the corner in the chat list's colours (ChatMark.css.ts):
// yellow spokes stepping round at work, red when it wants someone (blocked, failed), ringed in the page's ground.

///|
/// `maker`'s mark (of `runtime`) on its tile, `side` 16 (a line of a history's details), 20 (the chat's bar) or 28 (an
/// agent's card), `badge` (run, block, failed, or none) at its corner, said as `said` to a screen reader.
pub fn agent_mark(
  c : @ui.Ctx,
  maker : String,
  runtime : String,
  badge : String,
  side? : Double = 20.0,
  said? : String = "",
) -> Unit {
  let style = if side > 20.0 {
    agent_mark_28
  } else if side < 20.0 {
    agent_mark_16
  } else {
    agent_mark_20
  }
  c.box(style~, label=said, fn() {
    @sf.maker_mark(c, maker, runtime, (side * agent_logo_of).round()) |> ignore
    agent_badge(c, badge, side)
  })
  |> ignore
}

///|
/// The badge at a mark's corner `side` across (ui.css.ts agentMark ::after, ::before): red ringed 3 past it, the spokes
/// 2 past it.
fn agent_badge(c : @ui.Ctx, badge : String, side : Double) -> Unit {
  match badge {
    "block" | "failed" =>
      c.layer(fn() { c.box(style=agent_badge_red, tx=side - 9.0, ty=side - 9.0, fn() {  }) |> ignore }) |> ignore
    "run" =>
      c.layer(fn() {
        c.box(style=agent_badge_run, tx=side - 8.0, ty=side - 8.0, fn() {
          @sf.spokes(c, agent_spokes, @sf.mark_yellow) |> ignore
        })
        |> ignore
      })
      |> ignore
    _ => ()
  }
}

///|
/// How large the maker's mark is on its tile (ui.tsx: .62 of it, rounded), and the spokes at work.
let agent_logo_of : Double = 0.62

///|
let agent_spokes : Double = 10.0

///|
/// A tile 16 across, its corner 4.8; 20 (the chat's bar), 6; 28 (an agent's card), 8.4.
// kept across runs: a value (no field of it changes)
let agent_mark_16 : @ui.Style = @ui.style(
  w=S4,
  h=S4,
  radius=@sf.agent_mark_16_corner,
  bg=Neutral,
  align=ACenter,
  justify=JCenter,
)

///|
// kept across runs: a value (no field of it changes)
let agent_mark_20 : @ui.Style = @ui.css("w=S5 h=S5 radius=Md bg=Neutral align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let agent_mark_28 : @ui.Style = @ui.style(
  w=S7,
  h=S7,
  radius=@sf.agent_mark_28_corner,
  bg=Neutral,
  align=ACenter,
  justify=JCenter,
)

///|
/// Red, 12 across, ringed 2 in the page's ground; the spokes' box, 10.
// kept across runs: a value (no field of it changes)
let agent_badge_red : @ui.Style = @ui.style(w=S3, h=S3, radius=Full, bg=@sf.mark_red, border=B2, border_color=Bg)

///|
// kept across runs: a value (no field of it changes)
let agent_badge_run : @ui.Style = @ui.css("w=S2_5 h=S2_5")
