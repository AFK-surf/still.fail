// A workspace of the viewer's own made, and an invitation answered, from the rail's ＋ (ember web/src/cloud/workspace.tsx
// NewWorkspaceDialog, WorkspaceSwitcher's respond): its name, the account it is made by when more than one is signed
// in, the invite code once still.fail cloud asks for one (`workspace.create`); made, it is the one in view. An
// invitation joined (`invitation.accept`) is the one in view, said so; ignored (`invitation.decline`), said so too.

///|
/// The dialog as it is filled in: open, its name, the account chosen ("" the first), its code, whether one was asked
/// for, being made, why it could not be (the error's code and its words).
priv struct NewWorkspaceDialog {
  mut open : Bool
  name : @ui.Field
  code : @ui.Field
  mut owner : String
  mut asked : Bool
  mut creating : Bool
  mut error_code : String
  mut error : String
  /// its name's field to have the keys (autoFocus: the composer gives them up only to a field that takes them)
  mut focus : Bool
}

///|
let new_ws : NewWorkspaceDialog = {
  open: false,
  name: @ui.Field::new(),
  code: @ui.Field::new(),
  owner: "",
  asked: false,
  creating: false,
  error_code: "",
  error: "",
  focus: false,
}

///|
fn new_ws_reset() -> Unit {
  new_ws.open = false
  new_ws.name.set("")
  new_ws.code.set("")
  new_ws.owner = ""
  new_ws.asked = false
  new_ws.creating = false
  new_ws.error_code = ""
  new_ws.error = ""
  new_ws.focus = false
}

///|
/// The dialog opened, empty, its name's field taking what is typed.
fn open_new_workspace() -> Unit {
  new_ws_reset()
  new_ws.open = true
  new_ws.focus = true
}

///|
/// still.fail cloud's invite-code errors in words (cloud/api.ts INVITE_ERRORS); None for another.
fn invite_code_words(code : String) -> String? {
  match code {
    "invite_code_required" => Some(@sf.t("web-pages.errors.inviteCodeRequired"))
    "invite_code_invalid" => Some(@sf.t("web-pages.errors.inviteCodeInvalid"))
    "invite_code_used" => Some(@sf.t("web-pages.errors.inviteCodeUsed"))
    "invite_code_expired" => Some(@sf.t("web-pages.errors.inviteCodeExpired"))
    _ => None
  }
}

///|
/// The dialog (NewWorkspaceDialog), while it is open: 名称 (Enter makes it), 所属账号 among several accounts, 邀请码
/// once asked for (what is wrong with it under it, else what it is for), what else went wrong; 取消 and 新建.
fn new_workspace_dialog(c : @ui.Ctx, src : Source, pages : Pages) -> Unit {
  if !new_ws.open {
    return
  }
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
  let name = new_ws.name.text().trim(chars=" \n\t").to_owned()
  let code = new_ws.code.text().trim(chars=" \n\t").to_owned()
  let wants_code = invite_code_words(new_ws.error_code) is Some(_)
  let asking = new_ws.asked || wants_code
  let create = fn() {
    if name != "" && owner != "" && !new_ws.creating {
      make_workspace(src, pages, owner, name, code)
    }
  }
  let shown = @sf.dialog(
    c,
    "new-ws",
    true,
    @sf.t("web-pages.workspace.create"),
    description=@sf.t("web-pages.workspace.createLead"),
    footer=fn() {
      if @sf.button(c, @sf.t("common.cancel"), key="new-ws/cancel", tone=Ghost) {
        new_ws_reset()
      }
      if @sf.button(
          c,
          @sf.t("web-pages.workspace.createAction"),
          key="new-ws/create",
          tone=Primary,
          busy=new_ws.creating,
          disabled=name == "",
        ) {
        create()
      }
    },
    fn() {
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
          create()
        }
      })
      if accounts.length() > 1 {
        @sf.field(c, @sf.t("web-pages.workspace.owner"), fn() {
          let picked = @sf.select(
            c,
            "new-ws/owner",
            owner,
            accounts.map(fn(a) { (text(Some(a), "sub"), text(Some(a), "email")) }),
            label=@sf.t("web-pages.workspace.owner"),
          )
          new_ws.owner = picked
        })
      }
      if asking {
        @sf.field(
          c,
          @sf.t("web-pages.cloud.inviteCode"),
          fn() {
            let f = @sf.input(c, "new-ws/code", placeholder="XXXX-XXXX-XXXX", field=new_ws.code)
            if f.submitted && code != "" {
              create()
            }
          },
          hint=@sf.t("web-pages.workspace.codeHint", args=[("name", "still.fail")]),
          error=if wants_code && code != "" { new_ws.error } else { "" },
        )
      }
      if new_ws.error != "" && !wants_code {
        c.text(new_ws.error, style=new_ws_failed) |> ignore
      }
    },
  )
  if !shown && !new_ws.creating {
    new_ws_reset()
  }
}

///|
/// Makes it (`workspace.create`): the one in view once made, the dialog gone; else why, and the code's field once one
/// is wanted (sent every time: still.fail cloud looks at it only for an account not let in yet).
fn make_workspace(src : Source, pages : Pages, owner : String, name : String, code : String) -> Unit {
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
        new_ws_reset()
        to_workspace(src, pages, text(Some(v), "id"))
      }
      Err(e) => {
        new_ws.error_code = text(Some(e), "code")
        new_ws.error = match invite_code_words(new_ws.error_code) {
          Some(w) => w
          None => error_words(e)
        }
        if invite_code_words(new_ws.error_code) is Some(_) {
          new_ws.asked = true
        }
      }
    }
  })
}

///|
/// An invitation joined or ignored (WorkspaceSwitcher's respond): joined, its workspace the one in view, 已加入; ignored,
/// 已忽略邀请; why not, said so.
fn answer_invitation(src : Source, pages : Pages, account : Json?, id : String, join : Bool, name : String) -> Unit {
  if src.read_only {
    toast_later(read_only_words)
    return
  }
  let params : Json = { "account": Json::string(text(account, "sub")), "id": Json::string(id) }
  (src.call)(if join { "invitation.accept" } else { "invitation.decline" }, params, fn(r) {
    match r {
      Ok(v) =>
        if join {
          toast_later(@sf.t("web-pages.workspace.joined", args=[("name", name)]))
          to_workspace(src, pages, text(Some(v), "id"))
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

///|
/// Workspace `ws` the one in view (its page as it was left: the rail's switch).
fn to_workspace(src : Source, pages : Pages, ws : String) -> Unit {
  if ws == "" {
    return
  }
  app.picked = ws
  (src.call)("prefs.set", Json::object({ "workspace": Json::string(ws) }), fn(_) {  })
  (pages.home)()
}

///|
/// What else went wrong (fieldError: the meta's size, red).
// kept across runs: a value (no field of it changes)
let new_ws_failed : @ui.TextStyle = @ui.text_style(size=Xs, color=Danger, w=Full)
