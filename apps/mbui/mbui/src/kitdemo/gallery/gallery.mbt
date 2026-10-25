// The components' gallery's pages (main.mbt's `gallery`), the host checks it runs (textcheck, markscheck, viewcheck,
// sitecheck) and their tests: a package of its own, so its tests' program links no host (src/kitdemo is the app).

///|
/// The page in both themes, side by side.
pub fn gallery(c : @ui.Ctx, page : String) -> Unit {
  c.box(dir=Row, w=Fill(1.0), h=Fill(1.0), fn() {
    half(c, @ui.Theme::light(), page)
    half(c, @ui.Theme::dark(), page)
  })
  |> ignore
}

///|
fn half(c : @ui.Ctx, t : @ui.Theme, page : String) -> Unit {
  c.with_theme(t, fn() {
    c.scope(if t.dark { 2 } else { 1 }, fn() {
      c.box(w=Fill(1.0), h=Fill(1.0), bg=t.bg, pad=24.0, gap=18.0, clip=true, fn() {
        c.text(if t.dark { "Dark" } else { "Light" }, size=t.font_sm, weight=600, color=t.muted) |> ignore
        match page {
          "foundation" => foundation(c)
          "controls" => controls(c)
          "overlays" => overlays(c)
          "menus" => menus(c)
          "disclosure" => disclosure(c)
          _ => c.text("No page \"\{page}\"") |> ignore
        }
      })
      |> ignore
    })
  })
}

///|
/// A part of a page: its name over what it shows.
fn section(c : @ui.Ctx, title : String, body : () -> Unit) -> Unit {
  let t = c.theme()
  c.box(gap=8.0, fn() {
    c.text(title, size=12.0, weight=600, color=t.muted, wrap=false) |> ignore
    body()
  })
  |> ignore
}

///|
/// A row of what a section shows, onto more lines where the page is narrower than it (a phone's half).
fn line(c : @ui.Ctx, body : () -> Unit) -> Unit {
  c.box(dir=Row, flow=true, gap=8.0, align=ACenter, body) |> ignore
}
