// The new chat's pages with nothing to start on (new_first_station's, new_none_up's: new_alone's) as nodes of the
// window's tree, made once: a picture, a title and what it means in the middle of the page, each as the theme and the
// language change. Not yet what a page of the tree shows (the page's own nodes come with it).

///|
/// A page of a picture (`art`, by the theme), a title and what it means, in the middle of `parent` (new_alone's).
fn new_alone_node(parent : @view.View, art : () -> String, title : () -> String, note : () -> String) -> Unit {
  parent.box(fn(page) {
    // (new_page_box: all of it, what it holds in its middle both ways)
    page.width_share(Is(1.0)).height_share(Is(1.0)).lines_up(Is(Some(Middle))).lies_along(Is(Middle)) |> ignore
    page.box(fn(b) {
      // (new_alone_box: 32 in either side, its parts 10 apart and centred)
      b.width_share(Is(1.0)).padding(Is((32.0, 0.0, 32.0, 0.0))).gap(Is(10.0)).lines_up(Is(Some(Middle))) |> ignore
      @sf.drawable_node(b, art, new_scene_narrow_w) |> ignore
      b.box(fn(t) {
        t
        .width_share(Is(1.0))
        .words_centered(Is(true))
        .words(By(title))
        .words_look(By(fn() { @ui.style_words(new_alone_title) }))
        .ink(By(fn() { @ui.style_ink(new_alone_title) }))
        |> ignore
      })
      |> ignore
      b.box(fn(t) {
        t
        .width_share(Is(1.0))
        .words_centered(Is(true))
        .words(By(note))
        .words_look(By(fn() { @ui.style_words(new_sub) }))
        .ink(By(fn() { @ui.style_ink(new_sub) }))
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// No station at all in the workspace (new_first_station's): the first to add.
fn new_first_station_node(parent : @view.View) -> Unit {
  new_alone_node(
    parent,
    fn() { if @sf.theme().dark { "illus_no_station_dark" } else { "illus_no_station" } },
    fn() { @sf.t("android-settings.station.first") },
    fn() { @sf.t("android-settings.station.firstNote") },
  )
}

///|
/// None of them up (new_none_up's): said so, and how one comes.
fn new_none_up_node(parent : @view.View) -> Unit {
  new_alone_node(
    parent,
    fn() { if @sf.theme().dark { "illus_station_offline_dark" } else { "illus_station_offline" } },
    fn() { @sf.t("android-chat.new.offline.title") },
    fn() { @sf.t("android-chat.new.offline.text", args=[("app", "still.fail")]) },
  )
}
