// What a fixture mode opens over the app (its pages, what is put up over them), over the made-up core of the mode
// (src/sffixture): src/sffix's, the films', the layouts', the replays' and the app's own tests' one way. The app's
// own code calls none of it (detlint's fixture-import: the made-up core is only the tests' and the tools').

///|
/// What the modes of the cards and words set going as the chat opens: chat-answering's option under way, chat-pick's
/// word picked, chat-link-menu's link held, chat-ask's and chat-ask-long's question asked, chat-menu's and
/// chat-menu-choice's menu presented.
pub fn open_cards_fixture(mode : String) -> Unit {
  match mode {
    "chat-answering" => acting.doing["answer/" + seq_key("ws1/st1", 7.0, 8.0) + "/一起换"] = true
    // a question over the chat (the presenters' ask): a short one, its line given; or a long title and a hint taller than
    // a short window leaves it (its body scrolling in the panel)
    "chat-ask" => @sf.ask("重新命名这个对话", "保存", fn(_) {  }, value="周报整理", hint="名字会同步给所有成员。")
    "chat-ask-long" =>
      @sf.ask(
        "重新命名这个对话，新的名字会同步给这个工作区里的所有成员，并出现在他们的对话列表和通知里",
        "保存",
        fn(_) {  },
        value="周报整理",
        hint="改名后，旧的名字仍会出现在通知和历史记录里，直到它们更新；分享出去的链接不受影响，打开时显示新的名字。" +
        "这一段说明故意写得很长，好让它在窄小的窗口里折成很多行，比面板能放下的还高。再多写一些：搜索时新旧两个名字都能找到，" +
        "导出的记录里保留改名的时间。说明到此为止。",
      )
    // a word of the last post picked (its handles and its bar), once laid out (pick.mbt)
    "chat-pick" => {
      pk.ts = "ts11"
      pk.sel.key = "pick/ts11"
      pk.author = "Claude"
      pk.role = "agent"
      pk.sel.a = 4
      pk.sel.b = 6
      @sfbase.pick_told_given()
    }
    // a menu of the presenters' at a point over the chat: a heading, items with icons, a line, one in red, one not to
    // be chosen now; or a menu of choices, one chosen
    "chat-menu" =>
      @sf.menu(
        [
          Some(@sf.menu_item_of("这个对话", fn() {  }, heading=true)),
          Some(@sf.menu_item_of("复制链接", fn() {  }, icon="copy")),
          Some(@sf.menu_item_of("重命名", fn() {  }, icon="edit")),
          Some(@sf.menu_item_of("下载记录", fn() {  }, icon="download", disabled=true)),
          None,
          Some(@sf.menu_item_of("删除", fn() {  }, icon="trash", danger=true)),
        ],
        from=@sf.at_point(700.0, 300.0),
      )
    "chat-menu-choice" =>
      @sf.menu(
        [
          Some(@sf.menu_item_of("按时间", fn() {  }, chosen=true)),
          Some(@sf.menu_item_of("按名称", fn() {  }, chosen=false)),
          Some(@sf.menu_item_of("按大小", fn() {  }, chosen=false)),
        ],
        title="排序",
        from=@sf.at_point(700.0, 300.0),
      )
    // a short pick at a point: its title, the one chosen checked, one with what it is under its words, one with a value at
    // its end, one with its own mark (a station's)
    // a long pick at a point: its search over its list, scrolling past its most
    "chat-pick-long" =>
      @sf.pick(
        "选一个对话",
        Array::makei(14, fn(i) {
          @sf.choice("c\{i}", "对话 \{i + 1}", note=if i == 0 { "刚刚看过" } else { "" }, value=if i == 2 { "3 条新消息" } else { "" })
        }),
        "c1",
        fn(_) {  },
        from=@sf.at_point(700.0, 200.0),
      )
    "chat-pick-short" =>
      @sf.pick(
        "切换工作站",
        [
          @sf.choice("st1", "Studio", note="这台 Mac", mark=fn(c, size) { @sf.station_icon(c, "", "", size, @sf.theme().p.muted, here=true) }),
          @sf.choice("st2", "Mini1", value="离线", mark=fn(c, size) { @sf.station_icon(c, "", "", size, @sf.theme().p.muted) }),
          @sf.choice("st3", "ccvm", value="2 个任务"),
        ],
        "st1",
        fn(_) {  },
        from=@sf.at_point(700.0, 300.0),
      )
    // the bare address in the long answer held: its menu (link_menu.mbt)
    "chat-link-menu" => {
      link_menu_at("https://example.com/bench/list", 220.0, 360.0, 383.0)
    }
    _ => ()
  }
}

// ── Markdown's tables and code (MBUI_FIXTURE=chat-md) ───────────────────

///|
/// What a fixture mode of this slice opens over Home (sffix's main, as the app starts).
pub fn open_fixture(mode : String) -> Unit {
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  match mode {
    "history" | "history-reading" | "history-details" => {
      app.nav.push(Chat(r))
      app.nav.push(History(r, "s-c1", None))
      if mode == "history-details" {
        dui.history_tab = 1
      } else {
        @sfpages.history_open(["h2/group", "h2/group/1", "h4/group", "h4/group/0"])
      }
    }
    // the wide frame's (wide_panel.mbt): the chat's "…" open, its services' popover, what is opened beside it
    "chat-letters-pop" | "chat-opener-pop" | "chat-opened-pop" => @sfdesk.open_info_pop()
    "chat-jobs-pop" => {
      @sfdesk.open_jobs_pop()
      @sfdesk.open_job_pop("j-ci")
    }
    "home-attention" => @sfdesk.open_attention()
    // (what is beside it: the made-up core keeps it so, fixture.mbt fixture_chat_tabs)
    "chat-letters-side" => {
      dui.letters_open = ""
      dui.letters_held[r.station + "\u{1}" + r.session] = 7.0
    }
    "chat-model-pop" => @sfpages.open_triple(r.station, "session:s-c1")
    // (what is typed is looked for as the bar is first drawn)
    "chat-find" => @sfpages.find_preset(side_key(r), "截图")
    // the sheet that publishes the chat, what a snapshot would hold read (Publish.kt openPublish)
    "chat-publish" => {
      @sfpages.publish_set(r, 7.0, @sffixture.fix_preview())
    }
    // its station's card, from the agent's (Stations.kt openStationPeek)
    "chat-peek" => @settings.open_station_peek(r.station, from=Unanchored)
    _ => ()
  }
}

///|
/// What a fixture mode of this slice puts up over the chat once its source is made (open_fixture_src): the chat's
/// sheet, its letters (one opened), an agent's card, its jobs, a job.
fn open_decide_panels(mode : String, src : Source) -> Unit {
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  match mode {
    "chat-info" | "chat-letters-info" | "chat-info-pulls" | "chat-opener-info" | "chat-opened-info" => open_info(src, r)
    "chat-letters" | "chat-letters-many" => open_letters(src, r, 7.0)
    // what was said in it besides words (sfpages things.mbt), from its info
    "chat-things" => open_things(src, r, 7.0)
    "chat-letters-open" => {
      open_letters(src, r, 7.0)
      dui.letters_open = @sffixture.fix_letters_link
    }
    "chat-agent" | "chat-agent-unsaid" | "chat-agent-screens" => open_agent(src, r, "s-c1")
    "chat-jobs" => open_chat_jobs(src, r)
    "chat-job" => {
      dui.job_tab = 0
      open_job(src, r, "j-ci")
    }
    _ => ()
  }
}

///|
/// The fixture's drive pages opened as MBUI_FIXTURE says (see the top of this file).
pub fn open_drive_fixture(mode : String) -> Unit {
  let docs : DriveAt = { station: "ws1/st1", root: Some(@sffixture.fix_docs), path: "" }
  match mode {
    "files" => app.nav.push(Files)
    // a station's folders pinned, as a member sees them (its drive's page with no folder asked; chat_fixture.mbt)
    "drive-roots" => {
      app.nav.push(Files)
      app.nav.push(Drive({ ..docs, root: None }))
    }
    "drive" | "drive-loading" | "drive-upload" | "drive-download" | "drive-motion" => {
      app.nav.push(Files)
      app.nav.push(Drive(docs))
      // a file being downloaded, a folder being zipped for it (the core's downloads, downloads_fixture.mbt): their rows'
      // progress (keep.mbt)
      if mode == "drive-download" {
        @sffixture.fix_drive_downloads("ws1/st1", @sffixture.fix_docs)
      }
      if mode == "drive-upload" {
        let up = fn(name : String, size : Int, sent : Int, state : String, error : String) {
          ups.serial += 1
          ups.uploads.push({
            serial: ups.serial,
            station: "ws1/st1",
            root: @sffixture.fix_docs,
            dir: "",
            name: @signals.signal(name),
            bytes: Bytes::new(size),
            sent: @signals.signal(sent),
            state: @signals.signal(state),
            error: @signals.signal(error),
            replace: false,
            id: "",
          })
        }
        up("旅行照片.zip", 6291456, 2621440, "going", "")
        up("长篇小说.txt", 2048, 0, "taken", "")
        up("会议录音.m4a", 3145728, 0, "failed", "station 已离线")
        ups.pumping.set(true)
      }
    }
    "drive-sub" => {
      app.nav.push(Files)
      app.nav.push(Drive(docs))
      app.nav.push(Drive({ ..docs, path: "设计稿" }))
    }
    "drive-empty" => {
      app.nav.push(Files)
      app.nav.push(Drive({ ..docs, path: "空文件夹" }))
    }
    "reader" | "reader-bars" | "reader-contents" | "reader-layout" | "reader-md" => {
      let path = if mode == "reader-md" { "发布清单.md" } else { "长篇小说.txt" }
      let at = { ..docs, path }
      app.nav.push(Files)
      app.nav.push(Drive(docs))
      app.nav.push(DriveRead(at))
      let r = @sf.reading_for(reader_key(at))
      if mode != "reader" && mode != "reader-md" {
        r.chrome = true
      }
      if mode == "reader-contents" {
        r.panel = @sf.ReaderPanel::Contents
        r.contents_put = false
      }
      if mode == "reader-layout" {
        r.panel = @sf.ReaderPanel::Layout
        r.contents_put = false
      }
    }
    // (chat-station-files: ＋'s Station 文件 put up as the app's source is made, fixture_station_files)
    // (chat-attach-row: put in before the draft's kept files are read, so it is the first of the files' row)
    "chat-station-ref" | "chat-attach-row" =>
      @sffixture.fix_draft_ref("ws1/st1:s-c1", "发布清单.md", false, 4210.0, "path", true)
    // one sent as a file (up at the chat's station), a folder as a zip still going; a card's sheet open
    // (open_fixture_src)
    "chat-station-file" | "chat-station-sheet" => {
      @sffixture.fix_draft_ref("ws1/st1:s-c1", "发布清单.md", false, 4210.0, "file", true)
      @sffixture.fix_draft_ref("ws1/st1:s-c1", "设计稿", true, 0.0, "file", false)
    }
    // the player (play_fixture.mbt), a service's page (service_fixture.mbt)
    _ => {
      open_play_fixture(mode)
      open_service_fixture(mode)
      open_share_fixture(mode)
    }
  }
}

///|
/// What a fixture mode opens over Home before the first frame, as src/sffix (the screenshots' app) opens it: the
/// first row's chat (opened at a message from a notification for chat-flash…), its cards' states; the drive's pages;
/// a history, a chat's sheets; a new chat, the bar's panel, a place; a page of the settings.
pub fn open_fixture_mode(mode : String) -> Unit {
  let rich : ChatRef = {
    station: "ws1/st1",
    session: "s-c1",
    title: "整理发布清单",
    station_name: "Studio",
  }
  if mode == "chat-flash" || mode == "chat-flash-mine" {
    // opened from a notification at a message (Ana's, or yours), its flash held at its peak (slice 10's)
    open_chat_at(rich, if mode == "chat-flash" { 4.0 } else { 6.0 }, held=true)
  } else if mode.has_prefix("chat") {
    open_chat(rich)
    // the cards' states (chat_fixture.mbt): chat-cards, chat-answering
    open_cards_fixture(mode)
  }
  // what comes and goes, every kind of it (downloads_fixture.mbt fix_transfers): over Home its card on a small screen,
  // its chip in the sidebar's foot on a wide one, their list open (transfers.mbt); 本机缓存 with what is being brought
  if mode == "transfers" || mode == "home-transfers" || mode == "home-transfers-update" || mode == "settings-kept-fill" {
    @sffixture.fix_every_transfer("ws1/st1", "s-c1", @sffixture.fix_docs)
  }
  // a newer build ready that waits for the leave to install apps: its card over Home (home-update), over what comes
  // too (home-transfers-update, home-update-list)
  if mode == "home-transfers-update" || mode == "home-update" || mode == "home-update-list" {
    @sffixture.fixture_update("0.1.5640")
    @sffixture.fixture_update_goes("0.1.5640", "allow")
  }
  // a newer build ready where it is put in place at the person's word or as the app quits (a desktop's): 重启更新 in
  // the sidebar
  if mode == "home-update-ready" {
    @sffixture.fixture_update("0.1.5640")
    @sffixture.fixture_update_goes("0.1.5640", "ready", away=false)
  }
  if mode == "home-transfers" || mode == "home-transfers-update" || mode == "home-update-list" {
    @sfdesk.open_transfers()
  }
  if mode == "chat-keeping" {
    @sffixture.fix_keeping_message("ws1/st1", "s-c1")
  }
  // the drive's pages (src/sfapp/drive_fixture.mbt): files, drive…, reader…
  open_drive_fixture(mode)
  // slice 8's (src/sfapp/decide_fixture.mbt): a history, a chat's sheets
  open_fixture(mode)
  // a new chat (with its sheets), the bar's panel, a place: newchat_fixture.mbt
  open_mode(mode)
  // a station's screen (screen_fixture.mbt)
  @sfpages.open_screen_fixture(mode)
  if mode.has_prefix("settings") {
    let page = @settings.fixture_page(mode)
    open_setting(page)
    // (a page of theirs pictured: on the tape the page in use, brought over; the shell says its own only as it is first
    // drawn, so asked of the frame itself. Their list alone, the gear's: the list)
    if page != "home" {
      @sfdesk.bring_page()
    }
  }
  // 关于 as an update goes, as the host would say it (a film's: scripts/motion/update-flow.drive): offered; the
  // person's check (its bar sweeping); downloaded from 0 to whole; ready
  if mode == "settings-about-flow" {
    @sffixture.fixture_update("0.1.5283")
    let v = "0.1.5283"
    @sffixture.fix_later(1200.0, fn() { update.checking.set(true) })
    @sffixture.fix_later(2200.0, fn() {
      update.checking.set(false)
      @sffixture.fixture_update_goes(v, "downloading", percent=0)
    })
    for i in 1..=20 {
      @sffixture.fix_later(2200.0 + i.to_double() * 160.0, fn() {
        @sffixture.fixture_update_goes(v, "downloading", percent=i * 5)
      })
    }
    @sffixture.fix_later(5800.0, fn() { @sffixture.fixture_update_goes(v, "ready") })
  }
  // 关于 with a newer build on its way, on a device that sends usage statistics and error reports: its rows at their
  // fullest
  if mode == "settings-about" {
    @sffixture.fixture_update("0.1.5283")
    @sffixture.fixture_update_goes("0.1.5283", "downloading", percent=40)
    reporting_host.set(Some({ get: fn() { true }, set: fn(_) {  } }))
  }
  // the search open over Home, words typed (search_fixture.mbt)
  @sfpages.open_search_mode(mode)
  // a device not yet confirmed in the workspace's safe mode: lock-waiting, lock-finding, lock-code, lock-wrong (its
  // waiting page in the chats' place), lock-security (its security page), lock-upgrade (in the lock without its key:
  // the code typed on its security page)
  if mode == "lock-security" || mode == "lock-upgrade" {
    open_setting(@settings.fixture_page("settings-security"))
  }
  // ⌘/'s shortcuts at a glance (wide_keys.mbt keys_dialog)
  if mode == "keys-dialog" {
    @sfdesk.wide.keys_open.set(true)
  }
}

///|
/// The app as src/sffix starts it for `mode`, for a Tester made next (screens_wbtest.mbt): the app as at the start (reset:
/// whatever ran before in the process), the made-up source of the mode and what it opens before the first frame
/// (open_fixture_mode). The Tester keeps it as it starts (reset by hand).
pub fn fixture_app(mode : String) -> Source {
  reset()
  let src = @sffixture.fixture(mode)
  open_fixture_over(mode, src)
  src
}

///|
/// What `mode` opens over the app, over `src` (its own, or a test's made of it): its pages (open_fixture_mode), then
/// what is put up reading through `src` (open_fixture_src). The one way a mode is opened: sffix's, the films', the
/// screens' and the tests' alike.
pub fn open_fixture_over(mode : String, src : Source) -> Unit {
  open_fixture_mode(mode)
  open_fixture_src(mode, src)
}

///|
/// What the mode opens over the app once its source is made (what is put up reading through it), as open_fixture_mode
/// opens its pages: ＋'s Station 文件 (chat-station-files); a station's file's card pressed, its panel (chat-station-sheet);
/// the files' favorite picker with no one station in view, which station first (files-add-folder: its rows' grounds under the
/// pointer, the last in the dialog's foot corners); the card to share of the agents at work (share-card).
pub fn open_fixture_src(mode : String, src : Source) -> Unit {
  // slice 8's panels over the chat (decide_fixture.mbt)
  open_decide_panels(mode, src)
  if mode == "files-add-folder" {
    @sfdesk.add_favorite_folder(src, "ws1", @sfdesk.favorite_stations(src, "ws1"))
  }
  // (share-card-dark: over the dark theme; share-card-poster, -receipt, -terminal: in those looks)
  if mode == "share-card" || mode == "share-card-dark" || mode == "share-card-poster" || mode == "share-card-receipt" || mode == "share-card-terminal" {
    @sfpages.share_card_open(src, { id: "ws1", name: "星火工作室", emoji: "", icon: "", email: "lin@example.com" })
  }
  if mode == "chat-station-files" {
    fixture_station_files(src)
  }
  // the sessions Studio's machine kept, their list open over the new chat
  if mode == "newchat-machine" {
    @settings.fixture_machine_sessions(settings_core(src, { id: "ws1", name: "星火工作室", emoji: "", icon: "", email: "lin@example.com" }))
  }
  if mode == "chat-station-sheet" {
    @sfpages.ref_panel_put(src, "ws1/st1:s-c1", "ws1/st1", "ref-发布清单.md", "发布清单.md")
  }
}

///|
/// The first row's chat (opened by sffix for chat… modes): ＋'s Station 文件 in 文档, a file ticked.
fn fixture_station_files(src : Source) -> Unit {
  @sfdesk.station_files_pick(src, "ws1/st1:s-c1")
  @sfdesk.station_pick_set({ station: "ws1/st1", station_name: "Studio", root: @sffixture.fix_docs, root_name: "文档", path: "" }, [
    {
      station: "ws1/st1",
      station_name: "Studio",
      root: @sffixture.fix_docs,
      path: "发布清单.md",
      abs: @sffixture.fix_docs + "/发布清单.md",
      name: "发布清单.md",
      size: 4210.0,
      dir: false,
    },
  ])
}

///|
/// The screen's file read (`json`, its text): its topics and calls as a source over the made-up one's other parts
/// (pictures, files), and its pages opened over Home.
pub fn fixture_json(json : String) -> Source {
  let screen = @json.parse(json) catch { _ => abort("the screen's JSON does not parse") }
  let topics : Array[(Json, Json)] = []
  for t in items(Some(screen), "topics") {
    match (field(Some(t), "topic"), field(Some(t), "value")) {
      (Some(k), Some(v)) => topics.push((k, v))
      _ => ()
    }
  }
  let calls = items(Some(screen), "calls")
  let base = @sffixture.fixture("")
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      let key : Map[String, Json] = { "topic": Json::string(name) }
      for k, v in params {
        key[k] = v
      }
      let want = Json::object(key)
      match topics.iter().find_first(fn(t) { t.0 == want }) {
        Some((_, v)) => { value: Some(v), error: None, version: 1 }
        None => { value: None, error: None, version: 0 }
      }
    },
    call: fn(name, params, done) {
      // answered as the core's answer comes: an event from outside (its ticket ended: a frame for what it changed),
      // here at once
      let rt = @ui.runtime()
      let ticket = rt.outside_start("core: " + name)
      defer rt.outside_end(ticket)
      let said = match
        calls.iter().find_first(fn(c) { text(Some(c), "call") == name && field(Some(c), "params") == Some(params) }) {
        Some(c) => Some(c)
        None => calls.iter().find_first(fn(c) { text(Some(c), "call") == name })
      }
      match said {
        Some(c) => done(Ok(field(Some(c), "ok").unwrap_or(Json::null())))
        None =>
          done(Err({ "code": "unknown_call", "message": Json::string("the screen's JSON has no " + name) }))
      }
    },
  }
  for p in items(Some(screen), "open") {
    let station = text(Some(p), "station")
    let session = text(Some(p), "session")
    let r : ChatRef = { station, session, title: "", station_name: "" }
    match text(Some(p), "page") {
      "chat" => open_chat(r)
      "history" => app.nav.push(History(r, text(Some(p), "key"), None))
      "settings" => open_setting("home")
      _ => ()
    }
  }
  src
}

///|
/// The app as src/sffix starts it over a screen's JSON (MBUI_FIXTURE=json), for a Tester made next: the app as at the
/// start (whatever ran before in the process reset), then the
/// screen's source and its pages.
pub fn fixture_json_app(json : String) -> Source {
  reset()
  fixture_json(json)
}

///|
/// What a fixture mode opens over Home at the start (src/sffix): a new chat, with one of its sheets; the bar's panel;
/// a place.
pub fn open_mode(mode : String) -> Unit {
  if mode.has_prefix("newchat") {
    app.nav.rise(NewChat)
    if mode.has_prefix("newchat-crowded") || mode == "newchat-tall-model" {
      // (it starts on the model that runs on three runtimes, on the one of them its combination names)
      let n = @sffixture.new_fix
      n.crowded = true
      n.tall = mode == "newchat-tall-model"
      n.model = "deepseek-v4-1-flash"
      n.runtime = "dsh"
      n.d_model = n.model
      n.d_runtime = n.runtime
    }
    match mode {
      "newchat-station" => @sfpages.new_chat_ask("station")
      "newchat-preset" => @sfpages.new_chat_ask("preset")
      "newchat-preset-new" => @sfpages.new_chat_ask("preset-new")
      "newchat-preset-edit" => @sfpages.new_chat_ask("preset-edit")
      "newchat-preset-add" => @sfpages.new_chat_ask("preset-add")
      "newchat-preset-new-add" => @sfpages.new_chat_ask("preset-new-add")
      "newchat-preset-new-browse" => @sfpages.new_chat_ask("preset-new-browse")
      "newchat-preset-picked" => @sffixture.new_fix.preset = "p-sf"
      "newchat-model" | "newchat-crowded-model" | "newchat-tall-model" => @sfpages.new_chat_ask("model")
      _ => ()
    }
  } else if mode == "home-bars" {
    bar.open_panel(true)
  } else if mode == "place" {
    app.nav.replace(Files)
  } else if mode == "archived" {
    // 已归档: on the wide frame the sidebar's list of them, the newest beside it (lists.mbt archive_pane); laid out
    // Small its page
    app.nav.push(Archived)
  } else if mode.has_prefix("place-") {
    // a place of the rail's in the wide frame (wide_places.mbt): place-stations, place-profiles, place-connects,
    // place-usage
    app.nav.replace(Place(mode.view(start_offset=6).to_string()))
  } else if mode.has_prefix("files-") {
    // the files' page in the wide frame (wide_files.mbt) at Studio's 文档: files-columns (设计稿 open beside it, chosen),
    // files-tree (设计稿 opened in place), files-list, files-preview (发布清单.md previewed beside it), files-split (two
    // tabs, the one shown split)
    let docs : DriveAt = { station: "ws1/st1", root: Some(@sffixture.fix_docs), path: "" }
    app.nav.push(Files)
    // (in columns, 设计稿 open beside 文档: the page at it, chosen in the column before as coming to it chooses)
    app.nav.push(Drive(if mode == "files-columns" { { ..docs, path: "设计稿" } } else { docs }))
    // what the made-up core is told before the first frame: the way shown, a tree's folder open, what is chosen
    let browse = fn(params : Map[String, Json]) {
      let o : Map[String, Json] = {
        "owner": "page",
        "station": "ws1/st1",
        "root": Json::string(@sffixture.fix_docs),
        "path": "",
        "place": Json::string(@sfdesk.place_name("page/0")),
      }
      for k, v in params {
        o[k] = v
      }
      @sffixture.fix_browse_do(None, mode, "drive.browse", Json::object(o)) |> ignore
    }
    match mode {
      "files-columns" => @sffixture.fix_browse_prefs_set({ "driveViews": { "page": "columns" } }) |> ignore
      "files-favorite" | "files-favorite-dark" => {
        // A saved favorite and an old pinned root name the same folder, for a before/after comparison.
        let saved : Json = [{ "station": "ws1/st1", "root": Json::string(@sffixture.fix_docs), "path": "", "name": "文档" }]
        @sffixture.fix_browse_prefs_set({ "driveFavorites": { "ws1": Json::string(saved.stringify()) } }) |> ignore
      }
      "files-tree" => {
        @sffixture.fix_browse_prefs_set({ "driveViews": { "page": "tree" } }) |> ignore
        browse({ "act": "tree", "folder": "设计稿", "view": "tree" })
        @sfdesk.nav_open("ws1/st1")
      }
      "files-list" => @sffixture.fix_browse_prefs_set({ "driveViews": { "page": "list" } }) |> ignore
      // a copy asked about a name there (wide_files_drag.mbt): 说明.txt into 会议记录, which has one
      "files-clash" =>
        @sfdesk.drag_ask({
          into: { station: "ws1/st1", root: Some(@sffixture.fix_docs), path: "会议记录" },
          into_name: "会议记录",
          total: 1,
          clashes: [
            {
              name: "说明.txt",
              dir: false,
              size: 2048.0,
              station: "MBA",
              there: dv_entry(@sffixture.fix_entry("说明.txt", false, 320, "10/01")),
            },
          ],
          answers: {},
          all: false,
          done: fn(_) {  },
        })
      // what comes and goes open (the rail's key, transfers.mbt): a copy to MBA going (as the core says it)
      "files-transfers" => {
        @sffixture.fix_transfer({
          "from": { "station": "ws1/st1", "root": Json::string(@sffixture.fix_docs), "path": "", "names": ["演示录屏.mp4"] },
          "to": { "station": "ws1/st2", "root": "/Users/lin/照片", "path": "" },
          "move": false,
        })
        @sfdesk.transfers_open()
      }
      // the preview beside the list (wide_files_pane.mbt), 发布清单.md chosen
      "files-preview" => {
        @sffixture.fix_browse_prefs_set({ "driveViews": { "preview": "shown" } }) |> ignore
        browse({ "act": "choose", "view": "columns", "folder": "", "name": "发布清单.md" })
      }
      // two tabs, the one shown split: 文档 in front, the home beside it
      "files-split" =>
        @sffixture.fix_browse_prefs_set({ "filesTabs": { "ws1": Json::string(@sffixture.fix_split_tabs().stringify()) } }) |> ignore
      _ => ()
    }
  } else if mode == "rail-menu" {
    // the rail's menu, as a right click on 对话 opens it (rail.mbt rail_menu: the places not in it, each its ＋)
    @sfdesk.open_rail_menu("chats")
  } else if mode == "switcher" || mode == "switcher-found" {
    // ⌘K in the wide frame (sfdesk/switcher.mbt): with nothing typed, and with 签名 typed (what the search finds)
    @sfdesk.switcher_open_with(if mode == "switcher-found" { "签名" } else { "" })
  } else if mode == "home-sheet" || mode == "home-accounts" {
    // (home-accounts: two accounts signed in, what a new workspace asks which of)
    home_sheet_at_start.val = true
  }
}

///|
/// MBUI_FIXTURE=player-…: the made-up drive's film (the made-up core's: play_fixture) played over its folder's pages,
/// where its player stands.
fn open_play_fixture(mode : String) -> Unit {
  guard @sffixture.play_fixture(mode) is Some((at, pin)) else { return }
  let docs : DriveAt = { ..at, path: "" }
  app.nav.push(Files)
  app.nav.push(Drive(docs))
  app.nav.push(Drive({ ..docs, path: @sffixture.fix_films }))
  app.nav.push(DrivePlay(at))
  match pin {
    Some(s) => @sf.playing_for(reader_key(at)).media.pin(s)
    None => ()
  }
}

///|
/// MBUI_FIXTURE=service…: the first row's chat, its service's page over it.
fn open_service_fixture(mode : String) -> Unit {
  match mode {
    "service" | "service-sized" | "service-restart" | "service-stopped" => {
      app.nav.push(Chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }))
      app.nav.push(Service("ws1/st1", "j-web"))
      if mode == "service-sized" {
        svc_viewports[service_key("ws1/st1", "j-web")] = Some({ width: 390, height: Some(844) })
      }
    }
    _ => ()
  }
}

///|
/// MBUI_FIXTURE=share-in…: the sheet raised over Home.
fn open_share_fixture(mode : String) -> Unit {
  match mode {
    "share-in" | "share-in-stations" => {
      share_in.shared.set(Some(@sffixture.fix_shared))
      share_in.env_taken.set(true)
      raise_sheet(ShareSheet)
      share_in.raised.set(true)
      share_in.choosing.set(mode == "share-in-stations")
    }
    // files from another app's share sheet (ACTION_SEND_MULTIPLE): two pictures (the chat fixture's) and a document
    "share-in-files" => {
      share_in.shared.set(Some(("", None)))
      share_in.files.set([
        { name: "home-after.png", bytes: Bytes::new(182345), image: @sffixture.fixture_file("home-after.png") },
        { name: "compare.png", bytes: Bytes::new(96512), image: @sffixture.fixture_file("compare.png") },
        { name: "季度数据.csv", bytes: Bytes::new(23110), image: "" },
      ])
      share_in.env_taken.set(true)
      raise_sheet(ShareSheet)
      share_in.raised.set(true)
    }
    _ => ()
  }
}
