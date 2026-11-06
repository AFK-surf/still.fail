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

///|
/// Nothing to run a chat with yet (new_blocked's: FirstOne): what to add, whom to ask or where to pick models, by what
/// the core says blocks it (`v`'s `blocked`); the station chosen anew among several (new_station_node's capsule). In
/// the page's column (new_column's: 720 at most, 32 in), in its middle.
fn new_blocked_node(
  parent : @view.View,
  src : Source,
  w : () -> Workspace?,
  v : () -> Json?,
  station : () -> Json?,
) -> Unit {
  let address = fn() { text(station(), "station") }
  let name = fn() { new_station_words(station()) }
  let blocked = fn() { text(v(), "blocked") }
  parent.box(fn(page) {
    // (new_page_box, its column new_column's: as wide as the page less 32 either side, 720 at most, in its middle)
    page.width_share(Is(1.0)).height_share(Is(1.0)).lines_up(Is(Some(Middle))).lies_along(Is(Middle))
    .padding(Is((new_column_in, 0.0, new_column_in, 0.0))) |> ignore
    page.box(fn(col) {
      col
      .width_share(Is(1.0))
      .max_width(Is(Some(new_column_w)))
      .gap(Is(10.0))
      .lines_up(Is(Some(Middle)))
      |> ignore
      @sf.first_one_node(
        col,
        fn() {
          match blocked() {
            "profile" => @sf.t("web-main.newChat.addProfileFor", args=[("name", name())])
            "shared" => @sf.t("web-main.newChat.notShared", args=[("name", name())])
            _ => @sf.t("web-main.newChat.pickModels")
          }
        },
        lead=fn() {
          match blocked() {
            "profile" =>
              @sf.t("web-pages.profiles.lead", args=[("subscription", @sf.t("web-pages.profiles.leadSubscription"))])
            "shared" => text(v(), "problem")
            _ => @sf.t("web-main.newChat.noModelsLead", args=[("name", name())])
          }
        },
        art=fn(a) {
          @sf.drawable_node(a, fn() { if @sf.theme().dark { "illus_no_profile_dark" } else { "illus_no_profile" } }, new_scene_w)
          |> ignore
        },
        fn(row) {
          // (whom to ask: no button of its own, no room for one)
          row.show(fn() { blocked() != "shared" }, fn(b) {
            b.pick(fn() { blocked() == "profile" }, fn(slot, profile) {
              if profile {
                @sf.button_node(slot, fn() { @sf.t("web-main.newChat.addProfile") }, fn() {
                  open_page(Setting(@settings.Route::NewProfile(address())))
                }, tone=Primary, icon="plus")
                |> ignore
              } else {
                @sf.button_node(slot, fn() { @sf.t("web-main.newChat.goPickModels") }, fn() {
                  open_page(Setting(@settings.Route::Profiles(address())))
                }, tone=Primary)
                |> ignore
              }
            })
          })
          row.show(fn() { items(v(), "stations").length() > 1 }, fn(s) {
            new_station_node(s, src, w, v, station, fn() { false }, true)
          })
        },
      )
    })
    |> ignore
  })
  |> ignore
}
