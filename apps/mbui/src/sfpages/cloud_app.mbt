// Signed in with no workspace yet (the web's cloud/CloudApp.tsx Landing, InviteCodeForm; still.fail apps/android
// settings/screens/Workspaces.kt Landing, Blocked): the invitations
// waiting, each joined by its 加入 (`invitation.accept`); else said so, with 创建 workspace (`workspace.create`, the
// invite code still.fail cloud wants once it asks for one), 用邀请链接加入 (the invitation's sheet, links_sheet.mbt) and
// 切换账号. An account the app may not be used with (the core's `blocked`): why, its email, 退出此账号 or 切换账号.

///|
/// What the page has asked of the core and how it went: a workspace being made (with the code tried), why it could
/// not be (`created` its error's code and words), whether a code was asked for; the invitation being accepted, why it
/// could not be; the account being signed out, why it could not be.
priv struct LandingState {
  creating : @signals.Signal[Bool]
  code_tried : @signals.Signal[String]
  create_code : @signals.Signal[String]
  create_error : @signals.Signal[String]
  asked : @signals.Signal[Bool]
  accepting : @signals.Signal[String]
  accept_error : @signals.Signal[String]
  leaving : @signals.Signal[Bool]
  leave_error : @signals.Signal[String]
  code : @ui.Field
}

///|
let landing : LandingState = {
  creating: @signals.signal(false, same=fn(a, b) { a == b }),
  code_tried: @signals.signal("", same=fn(a, b) { a == b }),
  create_code: @signals.signal("", same=fn(a, b) { a == b }),
  create_error: @signals.signal("", same=fn(a, b) { a == b }),
  asked: @signals.signal(false, same=fn(a, b) { a == b }),
  accepting: @signals.signal("", same=fn(a, b) { a == b }),
  accept_error: @signals.signal("", same=fn(a, b) { a == b }),
  leaving: @signals.signal(false, same=fn(a, b) { a == b }),
  leave_error: @signals.signal("", same=fn(a, b) { a == b }),
  code: @ui.Field::new(),
}

///|
/// As at the start (tests).
pub fn landing_reset() -> Unit {
  landing.creating.set(false)
  landing.code_tried.set("")
  landing.create_code.set("")
  landing.create_error.set("")
  landing.asked.set(false)
  landing.accepting.set("")
  landing.accept_error.set("")
  landing.leaving.set(false)
  landing.leave_error.set("")
  landing.code.set("")
}

///|
/// still.fail cloud's invite-code errors and limits (LIMIT_ERRORS), by their codes.
pub fn invite_error_key(code : String) -> String? {
  match code {
    "invite_code_required" => Some("android-misc.invite.codeRequired")
    "invite_code_invalid" => Some("android-misc.invite.codeInvalid")
    "invite_code_used" => Some("android-misc.invite.codeUsed")
    "invite_code_expired" => Some("android-misc.invite.codeExpired")
    _ => None
  }
}

///|
/// An error in words: an invite code's or a limit's as still.fail says them, else the core's.
pub fn landing_error_words(e : Json) -> String {
  let code = text(Some(e), "code")
  match invite_error_key(code) {
    Some(k) => @sf.t(k)
    None =>
      match code {
        "too_many_workspaces" => @sf.t("android-misc.limit.workspaces")
        "too_many_members" => @sf.t("android-misc.limit.members")
        _ => error_words(e)
      }
  }
}

///|
/// The field: on the surface, a hairline round it, 12 round, 12 and 10 in.
// kept across runs: a value (no field of it changes)
pub let code_field : @ui.Style = @ui.css("w=Full px=S3 py=S2_5 radius=Xl bg=Surface border=B1 border_color=Line")

///|
/// Makes a workspace of the first account's own (named after it), with `code` when one was asked for: picked once
/// made; else why not, and whether a code is wanted.
fn create_workspace(src : Source, account : Json?, code : String) -> Unit {
  if src.read_only {
    toast_later(read_only_words)
    return
  }
  let sub = text(account, "sub")
  let name = match text(account, "name") {
    "" =>
      match text(account, "email").find("@") {
        Some(i) => text(account, "email").exact_view(end=i).to_owned()
        None => text(account, "email")
      }
    n => n
  }
  let params : Map[String, Json] = {
    "account": Json::string(sub),
    "name": Json::string(@sf.t("android-misc.workspace.defaultName", args=[("name", name)])),
  }
  if code != "" {
    params["invite_code"] = Json::string(code)
  }
  landing.creating.set(true)
  landing.code_tried.set(code)
  landing.create_error.set("")
  landing.create_code.set("")
  (src.call)("workspace.create", Json::object(params), fn(r) {
    landing.creating.set(false)
    match r {
      Ok(v) => @sfbase.pick_workspace(src, text(Some(v), "id"))
      Err(e) => {
        landing.create_code.set(text(Some(e), "code"))
        landing.create_error.set(landing_error_words(e))
        // once asked for a code, the form stays while codes are tried
        if invite_error_key(landing.create_code.get()) is Some(_) {
          landing.asked.set(true)
        }
      }
    }
  })
}

///|
/// An invitation accepted as `account` (Landing's join): the workspace joined is the one in view, at Home's top.
fn accept_invitation(src : Source, account : Json?, id : String) -> Unit {
  if src.read_only {
    toast_later(read_only_words)
    return
  }
  landing.accepting.set(id)
  landing.accept_error.set("")
  (src.call)("invitation.accept", { "account": Json::string(text(account, "sub")), "id": Json::string(id) }, fn(r) {
    landing.accepting.set("")
    match r {
      Ok(v) => {
        @sfbase.pick_workspace(src, text(Some(v), "id"))
        @sfbase.nav_home()
      }
      Err(e) => landing.accept_error.set(error_words(e))
    }
  })
}

///|
/// A role in words.
pub fn role_words(role : String) -> String {
  match role {
    "owner" => "Owner"
    "admin" => @sf.t("android-misc.role.admin")
    "member" => @sf.t("android-misc.role.member")
    r => r
  }
}
