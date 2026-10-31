// Choosing a workspace, making one and answering an invitation, in every tier (the web's cloud/workspace.tsx
// WorkspaceSwitcher, NewWorkspaceDialog; ember apps/android settings/screens/Workspaces.kt WorkspacesSheet,
// NewWorkspaceSheet): the workspaces, the one in use checked, what the others have waiting at their end, the
// invitations waiting (加入 `invitation.accept`, 忽略 `invitation.decline`), another account signed in, a new one.
// A new workspace: its name, the account it is made by when more than one is signed in, the invite code once
// still.fail cloud asks for one (`workspace.create`). Joined or made, it is the one in view, at its top. Shown by the
// library's panel (opened from what the frame gives: a sheet with a finger, beside it or in the window's middle with
// a mouse).

///|
/// The new workspace as it is filled in: its name, the account chosen ("" the first), its code, whether one was asked
/// for, being made, why it could not be (the error's code and its words); its name's field to have the keys as it
/// opens; what closes it once made. And the invitation being answered (+id joining, -id ignoring).
priv struct NewWorkspace {
  name : @ui.Field
  code : @ui.Field
  mut owner : String
  asked : @signals.Signal[Bool]
  creating : @signals.Signal[Bool]
  error_code : @signals.Signal[String]
  error : @signals.Signal[String]
  mut focus : Bool
  mut close : () -> Unit
  responding : @signals.Signal[String]
}

///|
// kept across runs: put back by workspace_reset (reset)
let new_ws : NewWorkspace = {
  name: @ui.Field::new(),
  code: @ui.Field::new(),
  owner: "",
  asked: @signals.signal(false, same=fn(a, b) { a == b }),
  creating: @signals.signal(false, same=fn(a, b) { a == b }),
  error_code: @signals.signal("", same=fn(a, b) { a == b }),
  error: @signals.signal("", same=fn(a, b) { a == b }),
  focus: false,
  close: fn() {  },
  responding: @signals.signal("", same=fn(a, b) { a == b }),
}

///|
fn workspace_reset() -> Unit {
  new_ws_cleared()
  new_ws.responding.set("")
  ws_menu.val = false
}

///|
/// The new workspace's fields as they are before it opens.
fn new_ws_cleared() -> Unit {
  new_ws.name.set("")
  new_ws.code.set("")
  new_ws.owner = ""
  new_ws.asked.set(false)
  new_ws.creating.set(false)
  new_ws.error_code.set("")
  new_ws.error.set("")
  new_ws.focus = false
  new_ws.close = fn() {  }
}

///|
/// The workspace `ws` the one in view, at its top (the prefs' `workspace`: the rail's switch, the list's row).
pub fn switch_workspace(src : Source, ws : String) -> Unit {
  if ws == "" {
    return
  }
  @sfbase.history_push()
  app.picked.set(ws)
  (src.call)("prefs.set", Json::object({ "workspace": Json::string(ws) }), fn(_) {  })
  @sfbase.nav_home()
}

// ── the workspaces ─────────────────────────────────────────────────────

///|
/// The workspace sheet; compact headings may request a content-sized panel instead of the usual tall list.
pub fn open_workspaces(src : Source, from : @sf.Anchor, compact? : Bool = false) -> Unit {
  @sf.panel(
    @sf.t("android-misc.workspace.sheet.title"),
    fn(c, close) {
      match @sfbase.workspace_in_view(src) {
        (Some(w), all, _, _) => workspaces_list(c, src, w, all, close, compact~)
        _ => ()
      }
    },
    from~,
    tall=if compact { 0.0 } else { workspaces_tall },
    grows=true,
  )
}

///|
let workspaces_tall : Double = 0.7

///|
/// The list: the one in use (checked) on a card, the invitations waiting, the others to switch to, then signing in
/// another account and a new one.
fn workspaces_list(c : @ui.Ctx, src : Source, w : Workspace, all : Array[Workspace], close : () -> Unit, compact~ : Bool) -> Unit {
  let marks = (src.topic)("workspaceMarks", { "workspace": Json::string(w.id) })
  let by_ws = field(marks.value, "workspaces")
  c.box(style=if compact { ws_list_compact } else { ws_list }, fn() {
    ws_label(c, @sf.t("android-misc.workspace.current"))
    c.box(style=ws_current, fn() {
      c.box(style=ws_card.then(@ui.style(bg=Data(@sf.theme().p.chip))), fn() {
        if workspace_row(c, "ws/" + w.id, w.name, w.email, true, Some(w), "", Json::null(), on_card=true) {
          close()
        }
      })
      |> ignore
    })
    |> ignore
    invitations(c, src, close)
    let others = all.filter(fn(x) { x.id != w.id })
    if others.length() > 0 {
      ws_label(c, @sf.t("android-misc.workspace.others"))
    }
    for o in others {
      let mark = field(by_ws, o.id).unwrap_or(Json::null())
      if workspace_row(c, "ws/" + o.id, o.name, o.email, false, Some(o), "", mark) {
        close()
        switch_workspace(src, o.id)
      }
    }
  })
  |> ignore
  c.box(style=ws_foot, fn() {
    if workspace_row(
        c,
        "ws-sign-in",
        @sf.t("android-misc.workspace.addAccount"),
        @sf.t("android-misc.workspace.addAccount.sub"),
        false,
        None,
        "log-in",
        Json::null(),
      ) {
      close()
      (src.sign_in)()
    }
    // (in place of the list: one over another is not stacked)
    if workspace_row(c, "ws-new", @sf.t("android-misc.workspace.new"), "", false, None, "plus", Json::null()) {
      close()
      open_new_workspace(src)
    }
  })
  |> ignore
}

///|
/// The list: what it holds, 24 over its foot, cut at its edges.
// kept across runs: a value (no field of it changes)
let ws_list : @ui.Style = @ui.css("w=Full h=Full pb=S6 clip")

///|
// kept across runs: a value (no field of it changes)
let ws_list_compact : @ui.Style = @ui.css("w=Full pb=S3")

///|
/// The one in use: on a card 12 in from the sides, 4 under its label, 16 over what follows.
// kept across runs: a value (no field of it changes)
let ws_current : @ui.Style = @ui.css("w=Full px=S3 pt=S1 pb=S4")

///|
/// A list card (Workspaces.kt RowsCard): its rows list_pad in, the list card's corner, on the chips' grey.
// kept across runs: a value (no field of it changes)
let ws_card : @ui.Style = @ui.style(w=Full, p=@sf.list_room, radius=@sf.list_card_radius, clip=true)

///|
/// Signing in another account and a new one: 8 under the list, 16 over the foot.
// kept across runs: a value (no field of it changes)
let ws_foot : @ui.Style = @ui.css("w=Full pt=S2 pb=S4")

///|
/// A part's label (13, muted): 20 in, 6 over it and 2 under.
fn ws_label(c : @ui.Ctx, label : String) -> Unit {
  c.box(style=ws_label_box, fn() { c.text(label, style=ws_label_words) |> ignore }) |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let ws_label_box : @ui.Style = @ui.css("px=S5 pt=S1_5 pb=S0_5")

///|
// kept across runs: a value (no field of it changes)
let ws_label_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false, leading=Font)

///|
/// A row (Controls.kt PickRow, Workspaces.kt WorkspaceRow): what, a line under it, a check on the chosen one; before
/// it a workspace's mark (or its letter) or an icon; after it what a workspace has waiting (`mark`: its marks). True
/// on the frame after it was pressed.
fn workspace_row(
  c : @ui.Ctx,
  key : String,
  label : String,
  sub : String,
  checked : Bool,
  lead : Workspace?,
  icon : String,
  mark : Json,
  on_card? : Bool = false,
) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  // on a list card (Parts.kt PickRow, LocalOnCard): its words card_pad from the card's edge, the card's list_pad in
  // already; on a sheet, 12 in and 8 more
  c.box(style=if on_card { ws_row_on_card } else { ws_row_in }, fn() {
    c.box(style=if on_card { ws_row_card } else { ws_row }, id~, fn() {
      match lead {
        Some(w) =>
          c.box(style=ws_row_lead, fn() {
            // (a GIF moving only for the workspace in use: Workspaces.kt, still for the others)
            workspace_mark(c, w, ws_row_mark, t.p.text, ws_row_letter, still=!checked)
          })
          |> ignore
        None => ()
      }
      if icon != "" {
        @sf.icon(c, icon, size=ws_row_icon, color=t.p.text) |> ignore
      }
      c.box(style=@sf.full_width, fn() {
        c.text(label, style=ws_row_label) |> ignore
        if sub != "" {
          c.text(sub, style=ws_row_sub) |> ignore
        }
      })
      |> ignore
      mark_counts(c, mark)
      if checked {
        @sf.icon(c, "check", size=ws_row_check, color=t.p.accent) |> ignore
      }
      // Workspaces.kt: clip(Smooth(LIST_ROW_CORNER)).clickable
      @motion.ripple(c, id, @sf.row_corner)
    })
    |> ignore
  })
  |> ignore
  c.clicked(id)
}

///|
/// On a sheet: 12 in from its sides; the row 8 more in, 12 over and under, 12 apart.
// kept across runs: a value (no field of it changes)
let ws_row_in : @ui.Style = @ui.css("w=Full px=S3")

///|
// kept across runs: a value (no field of it changes)
let ws_row_on_card : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let ws_row : @ui.Style = @ui.css("row w=Full px=S2 py=S3 gap=S3 align=ACenter")

///|
/// On a card: the card's list_pad in already, a row's room more (list_words_room: its words 16 from the card's edge).
// kept across runs: a value (no field of it changes)
let ws_row_card : @ui.Style = @ui.css("row w=Full py=S3 gap=S3 align=ACenter").then(@ui.style(px=@sf.list_words_room))

///|
/// A workspace's mark or its letter in a square 24 across: the mark 22, the letter 15 semibold, muted; an icon 20, the
/// check 14.
// kept across runs: a value (no field of it changes)
let ws_row_lead : @ui.Style = @ui.css("w=S6 h=S6 align=ACenter justify=JCenter")

///|
let ws_row_mark : Double = 22.0

///|
let ws_row_icon : Double = 20.0

///|
let ws_row_check : Double = 14.0

///|
// kept across runs: a value (no field of it changes)
let ws_row_letter : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, color=Muted, wrap=false, leading=Font)

///|
/// What, 15 on 21; the line under it 12 on 17, muted.
// kept across runs: a value (no field of it changes)
let ws_row_label : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ws_row_sub : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false, leading=@sf.pick_sub_line)

///|
/// What a workspace has waiting, after its name (SettingParts.kt MarkCounts): the chats its person takes part in that
/// went wrong, and those where it is their turn (waiting on them or unread), each its mark (chat_mark.mbt: red, blue)
/// and how many, 8 apart.
fn mark_counts(c : @ui.Ctx, mark : Json) -> Unit {
  let m = Some(mark)
  if text(m, "tone") == "" {
    return
  }
  // (read out as what it says: MarkCounts' contentDescription)
  c.box(style=ws_counts, label=text(m, "label"), fn() {
    for k in [("alert", ["alert"]), ("done", ["wait", "unread"])] {
      let n = k.1.fold(init=0, fn(n, x) { n + @sfbase.count(m, x) })
      if n > 0 {
        c.box(style=ws_count, fn() {
          chat_mark(c, k.0) |> ignore
          c.text("\{n}", style=ws_count_words) |> ignore
        })
        |> ignore
      }
    }
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let ws_counts : @ui.Style = @ui.css("row gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let ws_count : @ui.Style = @ui.css("row gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let ws_count_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false, leading=Font)

// ── the invitations ────────────────────────────────────────────────────

///|
/// The invitations waiting for any account signed in, each with the account it is for (the rail's ＋ shows them too).
pub fn invitations_waiting(src : Source) -> Array[(Json?, Json)] {
  let out : Array[(Json?, Json)] = []
  match (src.topic)("workspaces", {}).value {
    Some(Array(a)) =>
      for e in a {
        for i in items(Some(e), "invitations") {
          out.push((field(Some(e), "account"), i))
        }
      }
    _ => ()
  }
  out
}

///|
/// Who invited the viewer where (an invitation's line).
pub fn invited_you(inv : Json) -> String {
  let iv = Some(inv)
  @sf.t("android-misc.invite.invitedYou", args=[
    (
      "inviter",
      match text(iv, "inviter") {
        "" => @sf.t("android-misc.invite.someone")
        w => w
      },
    ),
    ("name", text(iv, "name")),
  ])
}

///|
/// The invitations in the list, under 邀请: who invited the viewer where, the account it is for, 加入 and 忽略.
fn invitations(c : @ui.Ctx, src : Source, close : () -> Unit) -> Unit {
  let pending = invitations_waiting(src)
  if pending.length() == 0 {
    return
  }
  ws_label(c, @sf.t("android-misc.invite.label"))
  for p in pending {
    let (account, inv) = p
    let iv = Some(inv)
    let id = text(iv, "id")
    let name = text(iv, "name")
    c.box(style=invite_line, fn() {
      c.box(style=@sf.full_width, fn() {
        c.text(invited_you(inv), style=invite_line_words) |> ignore
        c.text(text(account, "email"), style=invite_line_email) |> ignore
      })
      |> ignore
      let busy = new_ws.responding.get() != ""
      if @sf.button(c, @sf.t("android-misc.invite.join"), key="invite/join/" + id, tone=Primary, busy=new_ws.responding.get() == "+" + id) &&
        !busy {
        answer_invitation(src, account, id, true, name, close)
      }
      if @sf.button(c, @sf.t("android-misc.invite.ignore"), key="invite/ignore/" + id, busy=new_ws.responding.get() == "-" + id) &&
        !busy {
        answer_invitation(src, account, id, false, name, fn() {  })
      }
    })
    |> ignore
  }
}

///|
/// An invitation: 20 in, 8 over and under, 8 apart; its words the body's, the account under them small and muted.
// kept across runs: a value (no field of it changes)
let invite_line : @ui.Style = @ui.css("row w=Full px=S5 py=S2 gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let invite_line_words : @ui.TextStyle = @ui.text_style(size=Body, color=Fg, w=Full)

///|
// kept across runs: a value (no field of it changes)
let invite_line_email : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, w=Full)

///|
/// An invitation joined (its workspace the one in view, `joined` first: what showed it closed) or ignored, said so
/// once done; why not, said so.
pub fn answer_invitation(src : Source, account : Json?, id : String, join : Bool, name : String, joined : () -> Unit) -> Unit {
  if src.read_only {
    toast_later(read_only_words)
    return
  }
  new_ws.responding.set((if join { "+" } else { "-" }) + id)
  let params : Json = { "account": Json::string(text(account, "sub")), "id": Json::string(id) }
  (src.call)(if join { "invitation.accept" } else { "invitation.decline" }, params, fn(r) {
    new_ws.responding.set("")
    match r {
      Ok(v) =>
        if join {
          joined()
          switch_workspace(src, text(Some(v), "id"))
          toast_later(@sf.t("web-pages.workspace.joined", args=[("name", name)]))
        } else {
          toast_later(@sf.t("web-pages.workspace.ignored"))
        }
      Err(e) =>
        toast_later(
          @sf.t(if join { "web-pages.cloud.joinFailed" } else { "web-pages.workspace.ignoreFailed" }, args=[
            ("error", error_words(e)),
          ]),
        )
    }
  })
}

// ── a new workspace ────────────────────────────────────────────────────

///|
/// A new workspace (NewWorkspaceDialog), empty, its name's field taking what is typed: in the window's middle (a sheet
/// with a finger).
pub fn open_new_workspace(src : Source) -> Unit {
  new_ws_cleared()
  new_ws.focus = true
  @sf.panel(
    @sf.t("web-pages.workspace.create"),
    fn(c, close) { new_workspace_body(c, src, close) },
    from=Unanchored,
    description=@sf.t("web-pages.workspace.createLead"),
    foot=fn(c, close) { new_workspace_foot(c, src, close) },
    gone=fn() { if !new_ws.creating.get() { new_ws_cleared() } },
  )
}

///|
/// The account it is made by: the one chosen, else the first signed in.
fn new_ws_owner(src : Source) -> (Array[Json], String) {
  let accounts = match (src.topic)("accounts", {}).value {
    Some(Array(a)) => a
    _ => []
  }
  let owner = match accounts.iter().find_first(fn(a) { text(Some(a), "sub") == new_ws.owner }) {
    Some(a) => text(Some(a), "sub")
    None =>
      match accounts.get(0) {
        Some(a) => text(Some(a), "sub")
        None => ""
      }
  }
  (accounts, owner)
}

///|
/// Made, if it can be (a name, an account, nothing being made).
fn new_ws_create(src : Source, close : () -> Unit) -> Unit {
  let (_, owner) = new_ws_owner(src)
  let name = new_ws.name.text().trim(chars=" \n\t").to_string()
  let code = new_ws.code.text().trim(chars=" \n\t").to_string()
  if name != "" && owner != "" && !new_ws.creating.get() {
    new_ws.close = close
    make_workspace(src, owner, name, code)
  }
}

///|
/// What it holds: 名称 (Enter makes it), 所属账号 among several accounts, 邀请码 once asked for (what is wrong with it
/// under it, else what it is for), what else went wrong.
fn new_workspace_body(c : @ui.Ctx, src : Source, close : () -> Unit) -> Unit {
  let (accounts, owner) = new_ws_owner(src)
  let wants_code = invite_error_key(new_ws.error_code.get()) is Some(_)
  let code = new_ws.code.text().trim(chars=" \n\t").to_string()
  @sf.field(c, @sf.t("web-pages.settings.workspace.name"), fn() {
    let f = @sf.input(c, "new-ws/name", placeholder=@sf.t("web-pages.workspace.namePlaceholder"), field=new_ws.name)
    // (as it opens, till it has them)
    if new_ws.focus {
      if c.has_focus(c.id("new-ws/name")) {
        new_ws.focus = false
      } else {
        c.focus_editor("new-ws/name")
      }
    }
    if f.submitted {
      new_ws_create(src, close)
    }
  })
  if accounts.length() > 1 {
    @sf.field(c, @sf.t("web-pages.workspace.owner"), fn() {
      @sf.one_of(
        c,
        "new-ws/owner",
        owner,
        accounts.map(fn(a) { (text(Some(a), "sub"), text(Some(a), "email")) }),
        fn(v) { new_ws.owner = v },
        label=@sf.t("web-pages.workspace.owner"),
      )
    })
  }
  if new_ws.asked.get() || wants_code {
    @sf.field(
      c,
      @sf.t("web-pages.cloud.inviteCode"),
      fn() {
        let f = @sf.input(c, "new-ws/code", placeholder="XXXX-XXXX-XXXX", field=new_ws.code)
        if f.submitted && code != "" {
          new_ws_create(src, close)
        }
      },
      hint=@sf.t("web-pages.workspace.codeHint", args=[("name", "still.fail")]),
      error=if wants_code && code != "" { new_ws.error.get() } else { "" },
    )
  }
  if new_ws.error.get() != "" && !wants_code {
    c.text(new_ws.error.get(), style=new_ws_failed) |> ignore
  }
}

///|
/// Its foot: 取消 and 新建.
fn new_workspace_foot(c : @ui.Ctx, src : Source, close : () -> Unit) -> Unit {
  let name = new_ws.name.text().trim(chars=" \n\t").to_string()
  if @sf.button(c, @sf.t("common.cancel"), key="new-ws/cancel", tone=Ghost) {
    close()
    new_ws_cleared()
  }
  if @sf.button(
      c,
      @sf.t("web-pages.workspace.createAction"),
      key="new-ws/create",
      tone=Primary,
      busy=new_ws.creating.get(),
      disabled=name == "",
    ) {
    new_ws_create(src, close)
  }
}

///|
/// What else went wrong (fieldError: the meta's size, red).
// kept across runs: a value (no field of it changes)
let new_ws_failed : @ui.TextStyle = @ui.text_style(size=Meta, color=Danger, w=Full)

///|
/// Makes it (`workspace.create`): the one in view once made, what showed it closed; else why, and the code's field
/// once one is wanted (sent every time: still.fail cloud looks at it only for an account not let in yet).
fn make_workspace(src : Source, owner : String, name : String, code : String) -> Unit {
  if src.read_only {
    toast_later(read_only_words)
    return
  }
  let params : Map[String, Json] = { "account": Json::string(owner), "name": Json::string(name) }
  if code != "" {
    params["invite_code"] = Json::string(code)
  }
  new_ws.creating.set(true)
  new_ws.error.set("")
  new_ws.error_code.set("")
  (src.call)("workspace.create", Json::object(params), fn(r) {
    new_ws.creating.set(false)
    match r {
      Ok(v) => {
        let close = new_ws.close
        new_ws_cleared()
        close()
        switch_workspace(src, text(Some(v), "id"))
      }
      Err(e) => {
        new_ws.error_code.set(text(Some(e), "code"))
        new_ws.error.set(landing_error_words(e))
        if invite_error_key(new_ws.error_code.get()) is Some(_) {
          new_ws.asked.set(true)
        }
      }
    }
  })
}

// ── on the rail ────────────────────────────────────────────────────────

///|
/// What the rail gives its workspaces (sfdesk's rail.mbt): a square of its own on a ground, with its body, pressed by
/// an id (its node); a mark at a square's corner, on the rail's ground.
pub(all) struct SquareParts {
  square : (Int64, () -> Unit, Int) -> Int
  corner : (String) -> Unit
}

///|
/// Whether the ＋'s menu is open (the frame holds the sidebar out while it is).
// kept across runs: put back by workspace_reset (reset)
let ws_menu : Ref[Bool] = Ref(false)

///|
pub fn workspace_menu_open() -> Bool {
  ws_menu.val
}

///|
/// The workspaces at the rail's foot (Rail.tsx RailWorkspaces, Rail.css.ts workspaces, workspaceItem), on the rail's
/// squares (`parts`): each on a square, 6 apart; a letter on a square of its own, a mark (an icon, an emoji) on nothing, the places' ground under
/// the pointer; the one in view a short bar at its left; another with what waits in it (the core's marks' tone) its
/// mark at its corner. Over them the ＋ (making one, another account, invitations), always seen (the web's only as the
/// pointer comes over them). Pressed, that workspace.
pub fn workspace_squares(c : @ui.Ctx, src : Source, w : Workspace, all : Array[Workspace], parts : SquareParts) -> Unit {
  let t = @sf.theme()
  let marks = field((src.topic)("workspaceMarks", { "workspace": Json::string(w.id) }).value, "workspaces")
  let area = c.id("rail/workspaces")
  let add = c.id("rail/ws-add")
  let open = ws_menu.val
  let waiting = invitations_waiting(src).length() > 0
  let switch_to = fn(x : Workspace) { switch_workspace(src, x.id) }
  // ⌃1 … ⌃9 on a Mac (Alt elsewhere): the workspace at that place, as the web's keys (keymap.ts workspaceIndexOf)
  let held = if @ui.keys_system() == 0 { @ui.mod_ctrl } else { @ui.mod_alt }
  for k in 0..<dmin(9.0, all.length().to_double()).to_int() {
    if c.key_pressed(@ui.key_of_char((49 + k).unsafe_to_char()), mods=held, in_field=true) && all[k].id != w.id {
      switch_to(all[k])
    }
  }
  c.box(style=rail_ws_list, id=area, fn() {
    // the ＋
    // (pressed: opened or closed as it is let go, as it is then)
    c.on_press(add, fn() { ws_menu.val = !ws_menu.val })
    let hot = c.lit(add) || open
    let plus = (parts.square)(
      if hot { t.p.hover } else { 0L },
      fn() {
        // (always seen: what stands over it, what comes to this device, would else stand alone over a gap)
        let ink = if hot { t.p.text } else { t.p.muted }
        @sf.icon(c, "plus", size=rail_plus_size, color=ink) |> ignore
        // an invitation waiting: the accent's dot (workspace.css.ts inviteDot)
        if waiting {
          (parts.corner)("invite")
        }
      },
      add,
    )
    c.semantics(plus, Button, id=add, label=@sf.t("web-main.rail.addWorkspace"))
    @sf.tip(c, "rail/ws-add-tip", add, @sf.t("web-main.rail.addWorkspace"), side=Right)
    for x in all {
      let id = c.id("rail/ws/" + x.id)
      if x.id != w.id && c.clicked(id) {
        switch_to(x)
      }
      let on = x.id == w.id
      let hot = c.lit(id)
      let marked = workspace_marked(x)
      let square = (parts.square)(if !marked || hot { t.p.hover } else { 0L }, fn() {
        workspace_mark(c, x, rail_ws_mark, t.p.text, if on || hot { rail_letter_on } else { rail_letter })
        // the one in view: a short bar in the margin at its left
        if on {
          c.layer(fn() {
            c.box(style=rail_bar_at, fn() { c.box(style=rail_bar, tx=-rail_bar_out, fn() {  }) |> ignore }) |> ignore
          })
          |> ignore
        }
        // another's: what waits there, as its rows' marks
        let tone = if on { "" } else { text(field(marks, x.id), "tone") }
        if tone != "" {
          (parts.corner)(tone)
        }
      }, id)
      let said = text(field(marks, x.id), "label")
      let label = if on || said == "" { x.name } else { x.name + " · " + said }
      c.semantics(square, Button, id~, label~)
      @sf.tip(c, "rail/ws-tip/" + x.id, id, label, side=Right)
    }
  })
  |> ignore
  workspace_menu(c, src, add)
}

///|
/// The ＋'s icon (16), a workspace's mark (18).
let rail_plus_size : Double = 16.0

///|
let rail_ws_mark : Double = 18.0

///|
/// A workspace's letter (Rail.css.ts workspaceItem: textUi, 600), muted unless it is the one in view or pointed at:
/// its ink alone, the letter as big in each.
// kept across runs: a value (no field of it changes)
let rail_letter : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let rail_letter_on : @ui.TextStyle = rail_letter.then(@ui.text_style(color=Fg))

///|
/// The workspaces' column: 4 in from the rail's 38 (its squares where the places' grounds are), 4 above and under, 6
/// between.
// kept across runs: a value (no field of it changes)
let rail_ws_list : @ui.Style = @ui.css("pl=S1 pt=S1 pb=S1 gap=S1_5")

///|
/// The bar at the left of the workspace in view: 8 down its square, 6 out past it, 3 by 14, its corner 2.
// kept across runs: a value (no field of it changes)
let rail_bar_at : @ui.Style = @ui.css("pt=S2")

///|
// kept across runs: a value (no field of it changes)
let rail_bar : @ui.Style = @ui.style(w=Fixed(rail_bar_w), h=S3_5, radius=Sm, bg=Fg)

///|
let rail_bar_w : Double = 3.0

///|
let rail_bar_out : Double = 6.0

///|
/// The ＋'s menu, beside it, its foot level with the ＋'s (WorkspaceSwitcher `adder`): 新建 workspace, 添加另一个账号,
/// then the invitations waiting, each joined or ignored.
fn workspace_menu(c : @ui.Ctx, src : Source, add : Int) -> Unit {
  let entries : Array[@kit.Entry] = [
    @kit.menu_item("create", label=@sf.t("web-pages.workspace.create")),
    @kit.menu_item("account", label=@sf.t("web-pages.workspace.addAccount")),
  ]
  let icons : Map[String, String] = { "create": "plus", "account": "user-plus" }
  let pending = invitations_waiting(src)
  if pending.length() > 0 {
    entries.push(@kit.menu_separator())
    entries.push(@kit.menu_label(@sf.t("web-pages.workspace.invitations")))
    for p in pending {
      let iv = Some(p.1)
      let id = text(iv, "id")
      let inviter = match text(iv, "inviter") {
        "" => @sf.t("web-pages.cloud.someone")
        x => x
      }
      entries.push(
        @kit.menu_label(@sf.t("web-pages.workspace.invitedYou", args=[("inviter", inviter), ("name", text(iv, "name"))])),
      )
      entries.push(@kit.menu_item("join:" + id, label=@sf.t("web-pages.cloud.join")))
      entries.push(@kit.menu_item("ignore:" + id, label=@sf.t("web-pages.workspace.ignore")))
    }
  }
  // beside it, its foot level with the ＋'s (side right, align end, sideOffset 10)
  // (dismissed by the hand, Escape or a press outside it and the ＋: closed at that moment; closed as an item is chosen)
  let menu : Ref[@kit.Menu?] = Ref(None)
  c.with_dismissed(fn(_) { ws_menu.val = false }, fn() {
    menu.val = Some(
      @sf.dropdown(c, "rail/ws-menu", ws_menu.val, add, entries, icons, rail_ws_menu_w, side=Right, along=End, offset=rail_ws_menu_off),
    )
  })
  let m = menu.val.unwrap()
  if m.chosen is Some(_) {
    ws_menu.val = false
  }
  match m.chosen {
    Some("create") => open_new_workspace(src)
    Some("account") => (src.sign_in)()
    Some(v) if v.has_prefix("join:") || v.has_prefix("ignore:") => {
      let join = v.has_prefix("join:")
      let id = v.view(start_offset=if join { 5 } else { 7 }).to_string()
      for p in pending {
        if text(Some(p.1), "id") == id {
          answer_invitation(src, p.0, id, join, text(Some(p.1), "name"), fn() {  })
        }
      }
    }
    _ => ()
  }
}


///|
let rail_ws_menu_off : Double = 10.0

///|
/// The ＋'s menu (workspace.tsx accountMenu): 260 at least.
let rail_ws_menu_w : Double = 260.0
