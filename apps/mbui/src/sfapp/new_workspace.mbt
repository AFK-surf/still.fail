// A workspace of the viewer's own made from the workspaces' sheet (ember apps/android settings/screens/Workspaces.kt
// openNewWorkspace, NewWorkspaceSheet): its name, the account it is made by when more than one is signed in, and the
// invite code once still.fail cloud asks for one (`workspace.create`); made, it is the one in view, at Home's top.
// And the invitations waiting, in the workspaces' sheet: 加入 (`invitation.accept`) or 忽略 (`invitation.decline`).

///|
/// The new workspace's sheet as it is filled in: its name, the account chosen ("" the first), its code, what was
/// asked of the core and why it could not be.
priv struct NewWorkspace {
  name : @ui.Field
  code : @ui.Field
  mut owner : String
  mut creating : Bool
  mut error_code : String
  mut error : String
  mut asked : Bool
  /// the invitation being answered (+id joining, -id ignoring), and why it could not be
  mut responding : String
  mut respond_error : String
}

///|
let new_ws : NewWorkspace = {
  name: @ui.Field::new(),
  code: @ui.Field::new(),
  owner: "",
  creating: false,
  error_code: "",
  error: "",
  asked: false,
  responding: "",
  respond_error: "",
}

///|
/// As at the start (tests), and as the sheet opens.
fn new_ws_reset() -> Unit {
  new_ws.name.set("")
  new_ws.code.set("")
  new_ws.owner = ""
  new_ws.creating = false
  new_ws.error_code = ""
  new_ws.error = ""
  new_ws.asked = false
  new_ws.responding = ""
  new_ws.respond_error = ""
}

///|
/// The sheet opened, empty.
fn open_new_workspace() -> Unit {
  new_ws_reset()
  raise_sheet(NewWorkspace)
}

///|
/// Its body: 20 in from the sheet's sides, its parts 10 apart.
// kept across runs: a value (no field of it changes)
let new_ws_body : @ui.Style = @ui.css("w=Full px=S5 gap=S2_5")

///|
// kept across runs: a value (no field of it changes)
let new_ws_lead : @ui.TextStyle = @ui.text_style(size=Base, color=Muted, w=Full)

///|
/// A part's label (13, semibold, the ink).
// kept across runs: a value (no field of it changes)
let new_ws_label : @ui.TextStyle = @ui.text_style(size=Sm, weight=Semibold, color=Fg)

///|
/// What the code is for (12, muted), why it could not be (13, red).
// kept across runs: a value (no field of it changes)
let new_ws_note : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let new_ws_error : @ui.TextStyle = @ui.text_style(size=Sm, color=Danger, w=Full)

///|
/// Its buttons at the row's end, 8 apart, 6 over them and 24 under.
// kept across runs: a value (no field of it changes)
let new_ws_buttons : @ui.Style = @ui.css("row w=Full pt=S1_5 pb=S6 gap=S2 justify=JEnd")

///|
/// A field (Controls.kt Field), as the landing's code's: mbui's field in that look, one line, its words 15 on 21.
fn new_ws_field(c : @ui.Ctx, key : String, placeholder : String, field : @ui.Field) -> String {
  @kit.text_field(
    c,
    key,
    placeholder~,
    enter_sends=false,
    size=15.0,
    line=21.0,
    look=fn(c, s, editor) { c.box(id=s.id, style=code_field, editor) |> ignore },
    field~,
  ).text.trim(chars=" \n").to_string()
}

///|
/// The sheet (NewWorkspaceSheet).
fn new_workspace_sheet(c : @ui.Ctx, src : Source) -> Unit {
  let accounts = match (src.topic)("accounts", {}).value {
    Some(Array(a)) => a
    _ => []
  }
  let sub = match accounts.iter().find_first(fn(a) { text(Some(a), "sub") == new_ws.owner }) {
    Some(a) => text(Some(a), "sub")
    None =>
      match accounts.get(0) {
        Some(a) => text(Some(a), "sub")
        None => ""
      }
  }
  c.box(style=new_ws_body, fn() {
    c.text(tr("android-misc.workspace.new.text"), style=new_ws_lead) |> ignore
    c.text(tr("android-misc.workspace.name"), style=new_ws_label) |> ignore
    let name = new_ws_field(c, "new-ws/name", tr("android-misc.workspace.name.placeholder"), new_ws.name)
    if accounts.length() > 1 {
      c.text(tr("android-misc.workspace.account"), style=new_ws_label) |> ignore
      for a in accounts {
        let s = text(Some(a), "sub")
        if pick_row(c, "new-ws/account/" + s, text(Some(a), "email"), "", s == sub, None, "", Json::null()) {
          new_ws.owner = s
        }
      }
    }
    // (sent each time: still.fail cloud looks at it only for an account not let in yet, asking for it when wanted)
    let mut code = ""
    if new_ws.asked {
      c.text(tr("android-misc.invite.code"), style=new_ws_label) |> ignore
      code = new_ws_field(c, "new-ws/code", "XXXX-XXXX-XXXX", new_ws.code)
      if new_ws.error != "" && invite_error_key(new_ws.error_code) is Some(_) && code != "" {
        c.text(new_ws.error, style=new_ws_error) |> ignore
      } else {
        c.text(fill("android-misc.invite.codeNeeded", [("app", "still.fail")]), style=new_ws_note) |> ignore
      }
    }
    if new_ws.error != "" && invite_error_key(new_ws.error_code) is None {
      c.text(new_ws.error, style=new_ws_error) |> ignore
    }
    c.box(style=new_ws_buttons, fn() {
      if @settings.button(c, "new-ws/cancel", tr("common.cancel"), false) {
        lower_sheet()
      }
      if @settings.button(c, "new-ws/create", tr("android-misc.workspace.createButton"), true, busy=new_ws.creating, enabled=name != "" && sub != "") {
        make_new_workspace(src, sub, name, code)
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// Makes it: picked and Home at its top once made, the sheet gone; else why, and the code's field once one is wanted.
fn make_new_workspace(src : Source, sub : String, name : String, code : String) -> Unit {
  if src.read_only {
    toast_later(read_only_words)
    return
  }
  let params : Map[String, Json] = { "account": Json::string(sub), "name": Json::string(name) }
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
        lower_sheet()
        pick_workspace(src, text(Some(v), "id"))
        home()
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

///|
/// An invitation in the workspaces' sheet: who invited the viewer where, the account it is for, 加入 and 忽略; 20 in,
/// 8 over and under, 8 apart.
// kept across runs: a value (no field of it changes)
let invite_line : @ui.Style = @ui.css("row w=Full px=S5 py=S2 gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let invite_line_words : @ui.TextStyle = @ui.text_style(size=Lg, color=Fg, w=Full)

///|
// kept across runs: a value (no field of it changes)
let invite_line_email : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let invite_line_error : @ui.Style = @ui.css("w=Full px=S5")

///|
/// The invitations waiting for any account signed in (WorkspacesSheet), under 邀请.
fn waiting_invitations(c : @ui.Ctx, src : Source) -> Unit {
  let pending : Array[(Json?, Json)] = []
  match (src.topic)("workspaces", {}).value {
    Some(Array(a)) =>
      for e in a {
        for i in items(Some(e), "invitations") {
          pending.push((field(Some(e), "account"), i))
        }
      }
    _ => ()
  }
  if pending.length() == 0 {
    return
  }
  sheet_label(c, tr("android-misc.invite.label"))
  for p in pending {
    let (account, inv) = p
    let iv = Some(inv)
    let id = text(iv, "id")
    let name = text(iv, "name")
    c.box(style=invite_line, fn() {
      c.box(style=@sf.full_width, fn() {
        c.text(
          fill("android-misc.invite.invitedYou", [
            (
              "inviter",
              match text(iv, "inviter") {
                "" => tr("android-misc.invite.someone")
                w => w
              },
            ),
            ("name", name),
          ]),
          style=invite_line_words,
        )
        |> ignore
        c.text(text(account, "email"), style=invite_line_email) |> ignore
      })
      |> ignore
      let busy = new_ws.responding != ""
      if @settings.button(c, "invite/join/" + id, tr("android-misc.invite.join"), true, busy=new_ws.responding == "+" + id) && !busy {
        respond_invitation(src, account, id, true, name)
      }
      if @settings.button(c, "invite/ignore/" + id, tr("android-misc.invite.ignore"), false, busy=new_ws.responding == "-" + id) &&
        !busy {
        respond_invitation(src, account, id, false, name)
      }
    })
    |> ignore
  }
  if new_ws.respond_error != "" {
    c.box(style=invite_line_error, fn() { c.text(new_ws.respond_error, style=new_ws_error) |> ignore }) |> ignore
  }
}

///|
/// Joins (the workspace joined in view, Home at its top) or ignores an invitation, said so once done.
fn respond_invitation(src : Source, account : Json?, id : String, join : Bool, name : String) -> Unit {
  if src.read_only {
    toast_later(read_only_words)
    return
  }
  new_ws.responding = (if join { "+" } else { "-" }) + id
  new_ws.respond_error = ""
  let params : Json = { "account": Json::string(text(account, "sub")), "id": Json::string(id) }
  (src.call)(if join { "invitation.accept" } else { "invitation.decline" }, params, fn(r) {
    new_ws.responding = ""
    match r {
      Ok(v) =>
        if join {
          lower_sheet()
          pick_workspace(src, text(Some(v), "id"))
          home()
          toast_later(fill("android-misc.invite.joined", [("name", name)]))
        } else {
          toast_later(tr("android-misc.invite.ignored"))
        }
      Err(e) => new_ws.respond_error = error_words(e)
    }
  })
}
