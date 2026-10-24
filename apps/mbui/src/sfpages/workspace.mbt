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
  mut asked : Bool
  mut creating : Bool
  mut error_code : String
  mut error : String
  mut focus : Bool
  mut close : () -> Unit
  mut responding : String
}

///|
// kept across runs: put back by workspace_reset (reset)
let new_ws : NewWorkspace = {
  name: @ui.Field::new(),
  code: @ui.Field::new(),
  owner: "",
  asked: false,
  creating: false,
  error_code: "",
  error: "",
  focus: false,
  close: fn() {  },
  responding: "",
}

///|
fn workspace_reset() -> Unit {
  new_ws_cleared()
  new_ws.responding = ""
}

///|
/// The new workspace's fields as they are before it opens.
fn new_ws_cleared() -> Unit {
  new_ws.name.set("")
  new_ws.code.set("")
  new_ws.owner = ""
  new_ws.asked = false
  new_ws.creating = false
  new_ws.error_code = ""
  new_ws.error = ""
  new_ws.focus = false
  new_ws.close = fn() {  }
}

///|
/// The workspace `ws` the one in view, at its top (the prefs' `workspace`: the rail's switch, the list's row).
pub fn switch_workspace(src : Source, ws : String) -> Unit {
  if ws == "" {
    return
  }
  app.picked = ws
  (src.call)("prefs.set", Json::object({ "workspace": Json::string(ws) }), fn(_) {  })
  @sfbase.nav_home()
}

// ── the workspaces ─────────────────────────────────────────────────────

///|
/// The workspaces (WorkspacesSheet), opened by `from` (its name over the chats): 70% of the window, dragged between
/// half and nearly all of it as a sheet; the one in view and the others as they are each frame.
pub fn open_workspaces(src : Source, from : @sf.Anchor) -> Unit {
  @sf.panel(
    @sf.t("android-misc.workspace.sheet.title"),
    fn(c, close) {
      match @sfbase.workspace_in_view(src) {
        (Some(w), all, _, _) => workspaces_list(c, src, w, all, close)
        _ => ()
      }
    },
    from~,
    tall=workspaces_tall,
    grows=true,
  )
}

///|
let workspaces_tall : Double = 0.7

///|
/// The list: the one in use (checked) on a card, the invitations waiting, the others to switch to, then signing in
/// another account and a new one.
fn workspaces_list(c : @ui.Ctx, src : Source, w : Workspace, all : Array[Workspace], close : () -> Unit) -> Unit {
  let marks = (src.topic)("workspaceMarks", { "workspace": Json::string(w.id) })
  let by_ws = field(marks.value, "workspaces")
  let any_marked = all.iter().any(fn(x) { @sf.has_station_mark(x.emoji, x.icon) })
  let lead = fn(x : Workspace) { if any_marked { Some(x) } else { None } }
  c.box(style=ws_list, fn() {
    ws_label(c, @sf.t("android-misc.workspace.current"))
    c.box(style=ws_current, fn() {
      c.box(style=ws_card.then(@ui.style(bg=Data(@sf.theme().p.chip))), fn() {
        if workspace_row(c, "ws/" + w.id, w.name, w.email, true, lead(w), "", Json::null(), on_card=true) {
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
      if workspace_row(c, "ws/" + o.id, o.name, o.email, false, lead(o), "", mark) {
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
/// The one in use: on a card 12 in from the sides, 4 under its label, 16 over what follows.
// kept across runs: a value (no field of it changes)
let ws_current : @ui.Style = @ui.css("w=Full px=S3 pt=S1 pb=S4")

///|
/// A list card (Workspaces.kt RowsCard): its rows 8 in, the list card's corner, on the chips' grey.
// kept across runs: a value (no field of it changes)
let ws_card : @ui.Style = @ui.style(w=Full, p=S2, radius=@sf.list_card_radius, clip=true)

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
let ws_label_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, wrap=false, leading=Font)

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
            if @sf.has_station_mark(w.emoji, w.icon) {
              // a GIF moving only for the workspace in use (Workspaces.kt: still for the others)
              @sf.station_mark(c, w.emoji, w.icon, ws_row_mark, t.p.text, still=!checked)
            } else {
              c.text(@sf.initial(w.name), style=ws_row_letter) |> ignore
            }
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
/// On a card: the card's 8 in already, 12 more (its words card_pad, 20, from the card's edge).
// kept across runs: a value (no field of it changes)
let ws_row_card : @ui.Style = @ui.css("row w=Full px=S3 py=S3 gap=S3 align=ACenter")

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
let ws_row_letter : @ui.TextStyle = @ui.text_style(size=Lg, weight=Semibold, color=Muted, wrap=false, leading=Font)

///|
/// What, 15 on 21; the line under it 12 on 17, muted.
// kept across runs: a value (no field of it changes)
let ws_row_label : @ui.TextStyle = @ui.text_style(size=Lg, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ws_row_sub : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false, leading=@sf.pick_sub_line)

///|
/// What a workspace has waiting, after its name (SettingParts.kt MarkCounts): the chats its person takes part in that
/// want them, that wait on them, that are unread, each its mark (chat_mark.mbt) and how many, 8 apart.
fn mark_counts(c : @ui.Ctx, mark : Json) -> Unit {
  let m = Some(mark)
  if text(m, "tone") == "" {
    return
  }
  // (read out as what it says: MarkCounts' contentDescription)
  c.box(style=ws_counts, label=text(m, "label"), fn() {
    for k in [("alert", "alert"), ("wait", "wait"), ("done", "unread")] {
      let n = @sfbase.count(m, k.1)
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
let ws_count_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false, leading=Font)

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
      let busy = new_ws.responding != ""
      if @settings.button(c, "invite/join/" + id, @sf.t("android-misc.invite.join"), true, busy=new_ws.responding == "+" + id) &&
        !busy {
        answer_invitation(src, account, id, true, name, close)
      }
      if @settings.button(c, "invite/ignore/" + id, @sf.t("android-misc.invite.ignore"), false, busy=new_ws.responding == "-" + id) &&
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
let invite_line_words : @ui.TextStyle = @ui.text_style(size=Lg, color=Fg, w=Full)

///|
// kept across runs: a value (no field of it changes)
let invite_line_email : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, w=Full)

///|
/// An invitation joined (its workspace the one in view, `joined` first: what showed it closed) or ignored, said so
/// once done; why not, said so.
pub fn answer_invitation(src : Source, account : Json?, id : String, join : Bool, name : String, joined : () -> Unit) -> Unit {
  if src.read_only {
    toast_later(read_only_words)
    return
  }
  new_ws.responding = (if join { "+" } else { "-" }) + id
  let params : Json = { "account": Json::string(text(account, "sub")), "id": Json::string(id) }
  (src.call)(if join { "invitation.accept" } else { "invitation.decline" }, params, fn(r) {
    new_ws.responding = ""
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
    gone=fn() { if !new_ws.creating { new_ws_cleared() } },
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
  if name != "" && owner != "" && !new_ws.creating {
    new_ws.close = close
    make_workspace(src, owner, name, code)
  }
}

///|
/// What it holds: 名称 (Enter makes it), 所属账号 among several accounts, 邀请码 once asked for (what is wrong with it
/// under it, else what it is for), what else went wrong.
fn new_workspace_body(c : @ui.Ctx, src : Source, close : () -> Unit) -> Unit {
  let (accounts, owner) = new_ws_owner(src)
  let wants_code = invite_error_key(new_ws.error_code) is Some(_)
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
      new_ws.owner = @sf.select(
        c,
        "new-ws/owner",
        owner,
        accounts.map(fn(a) { (text(Some(a), "sub"), text(Some(a), "email")) }),
        label=@sf.t("web-pages.workspace.owner"),
      )
    })
  }
  if new_ws.asked || wants_code {
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
      error=if wants_code && code != "" { new_ws.error } else { "" },
    )
  }
  if new_ws.error != "" && !wants_code {
    c.text(new_ws.error, style=new_ws_failed) |> ignore
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
      busy=new_ws.creating,
      disabled=name == "",
    ) {
    new_ws_create(src, close)
  }
}

///|
/// What else went wrong (fieldError: the meta's size, red).
// kept across runs: a value (no field of it changes)
let new_ws_failed : @ui.TextStyle = @ui.text_style(size=Xs, color=Danger, w=Full)

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
  new_ws.creating = true
  new_ws.error = ""
  new_ws.error_code = ""
  (src.call)("workspace.create", Json::object(params), fn(r) {
    new_ws.creating = false
    match r {
      Ok(v) => {
        let close = new_ws.close
        new_ws_cleared()
        close()
        switch_workspace(src, text(Some(v), "id"))
      }
      Err(e) => {
        new_ws.error_code = text(Some(e), "code")
        new_ws.error = landing_error_words(e)
        if invite_error_key(new_ws.error_code) is Some(_) {
          new_ws.asked = true
        }
      }
    }
  })
}
