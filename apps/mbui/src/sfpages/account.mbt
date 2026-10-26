// 账号, one page in every frame (web/src/cloud/settings.tsx AccountSettings; the narrow app's mobile/Me.tsx), the same
// on every width (the user, 2026-10-26: 「设置感觉很乱」; it was four sections and two cards wide, one card narrow): the
// accounts on this device on one card, the one in view first with who it is (its picture, name, email and how it
// signs in) and signing out of it, the others each signed out of by itself, another added; where it is signed in (each
// device, signed out from here but this one); deleting the account, in red at the foot. Signing out and deleting
// asked first (@sf.confirm).

///|
/// 账号 (AccountSettings, MeScreen).
pub fn me_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame) -> Unit {
  let look = look_of(c)
  let name = if here.person != "" { here.person } else { here.email }
  let how = if here.sub.has_prefix("em-") || here.sub.has_prefix("pw-") {
    @sf.t("web-pages.settings.account.email")
  } else {
    @sf.t("web-pages.settings.account.google")
  }
  let accounts = match (core.topic)("accounts", Map::new()).value {
    Some(Array(a)) => a
    _ => []
  }
  let others = accounts.filter(fn(a) { text(Some(a), "sub") != here.sub })
  // signing out of one: asked first, then the chats (the account in view goes with it)
  let sign_out = fn(sub : String, email : String) {
    @sf.confirm(
      @sf.t("web-pages.settings.account.signOutConfirm", args=[("email", email)]),
      @sf.t("web-pages.settings.account.signOutConfirmBody"),
      @sf.t("web-pages.settings.account.signOutAction"),
      fn() {
        if sub == here.sub {
          (core.home)()
        }
        @settings.act(
          core,
          @sf.t("web-pages.settings.account.signOut"),
          "auth.signOut",
          obj([("account", str(sub))]),
          done=@sf.t("web-pages.settings.account.signedOut", args=[("email", email)]),
        )
      },
    )
  }
  let delete = fn() {
    @sf.confirm(
      @sf.t("web-pages.settings.account.delete"),
      @sf.t("web-pages.settings.account.deleteConfirmBody", args=[("email", here.email)]),
      @sf.t("web-pages.settings.account.deleteAction"),
      danger=true,
      fn() {
        (core.home)()
        @settings.act(
          core,
          @sf.t("web-pages.settings.account.deleteAction"),
          "auth.deleteAccount",
          obj([("account", str(here.sub))]),
          done=@sf.t("web-pages.settings.account.deleted", args=[("email", here.email)]),
        )
      },
    )
  }
  let blocks : Array[() -> Unit] = []
  // the accounts on this device on one card (Me.tsx): the one in view with who it is, then the others, each signed out
  // of by itself, another added
  blocks.push(fn() {
    @sf.group(c, fn() {
      @sf.link_row(
        c,
        "",
        name,
        note=here.email + " · " + how,
        strong=true,
        goes=false,
        lead=fn() { avatar(c, core, here.email, name, acc_picture, picture=here.picture) },
        tail=fn() {
          let words = if others.length() > 0 {
            @sf.t("android-settings.me.signOut")
          } else {
            @sf.t("android-settings.me.signOutOnly")
          }
          // (words alone: on its title's line, its email and how it signs in as close under it as a row's without one)
          @sf.line_end(c, fn() {
            if @sf.button(c, words, key="sign-out/" + here.sub, tone=Ghost) {
              sign_out(here.sub, here.email)
            }
          })
        },
      )
      |> ignore
      for a in others {
        let sub = text(Some(a), "sub")
        let email = text(Some(a), "email")
        @sf.link_row(c, "", email, goes=false, tail=fn() {
          if @sf.button(c, @sf.t("android-settings.me.signOut"), key="sign-out/" + sub, tone=Ghost) {
            sign_out(sub, email)
          }
        })
        |> ignore
      }
      if @sf.link_row(c, "add-account", @sf.t("android-settings.me.addAccount"), chevron=false) {
        (core.sign_in)()
      }
    })
  })
  blocks.push(fn() {
    @sf.section(c, @sf.t("web-pages.settings.account.sessions"), heads=true, note=@sf.t("web-pages.settings.account.sessionsLead", args=[("name", "still.fail")]), fn() {
      acc_devices(c, core, look, here)
    })
  })
  // deleting the account in view, at the foot, in red (Me.tsx)
  blocks.push(fn() {
    @sf.group(c, fn() {
      if @sf.link_row(c, "delete-account", @sf.t("android-settings.me.delete"), danger=true, chevron=false) {
        delete()
      }
    })
  })
  @sf.page(c, on_back=core.pop, frame~, "me", @sf.t("android-settings.me.title"), blocks)
}

///|
/// Where the account is signed in (the `loginSessions` topic): each device's name (this one marked 当前), when it signed
/// in and until when; 退出 on the others (`loginSession.revoke`). Narrow, on a card. Read the first time, rows' shapes
/// where their card's rows will be (settings.tsx: Waiting, 3).
fn acc_devices(c : @ui.Ctx, core : Core, look : Look, here : Here) -> Unit {
  let topic = (core.topic)("loginSessions", { "account": str(here.sub) })
  let list = match topic.value {
    Some(Array(a)) => a
    _ => {
      match topic.error {
        Some(e) => @sf.page_note(c, @sf.t("web-pages.settings.account.sessionsFailed", args=[("error", error_text(e))]), bad=true)
        None => @sf.waiting(c, fn() { devices_list(c, core.quiet(), look, here, devices_sample()) }, text=@sf.t("common.reading"))
      }
      return
    }
  }
  devices_list(c, core, look, here, list)
}

///|
/// The devices the account is signed in on (`list`): each its name, 当前 or 退出, when it signed in and until when.
fn devices_list(c : @ui.Ctx, core : Core, look : Look, here : Here, list : Array[Json]) -> Unit {
  let narrow = look == Narrow
  @sf.group(c, fn() {
    for d in list {
      let dv = Some(d)
      let id = text(dv, "id")
      let current = flag(dv, "current")
      // its name, 当前 or 退出 on its first line; when it signed in and until when under them, a line of its own
      c.box(style=if narrow { @sf.pg_said_row } else { desk_list_row }, fn() {
        @sf.row_lines(c, spaced=true, fn() {
          c.box(style=desk_named.then(acc_device_head), fn() {
            c.text(
              match text(dv, "name") {
                "" => @sf.t("web-pages.settings.account.unnamedDevice")
                n => n
              },
              style=if narrow { acc_device_narrow } else { desk_list_title },
            )
            |> ignore
            // (当前 after its name, wide and narrow alike: clear of its row's corners)
            if current {
              you(c, @sf.t("web-pages.settings.account.here"))
            }
          })
          |> ignore
          if !current {
            @sf.line_end(c, fn() {
              let revoking = is_doing(core, ["loginSession.revoke"], [("id", id)])
              if @sf.button(c, @sf.t("web-pages.settings.account.revoke"), key="revoke/" + id, tone=Ghost, busy=revoking) {
                @settings.act(
                  core,
                  @sf.t("web-pages.settings.account.revoke"),
                  "loginSession.revoke",
                  obj([("id", str(id)), ("account", str(here.sub))]),
                  done=@sf.t("web-pages.settings.account.revoked"),
                )
              }
            })
          }
        }, fn() {
          let times = @sf.t("web-pages.settings.account.sessionTimes", args=[("time", stamp(dv, "created_at", "ago")), ("until", stamp(dv, "expires_at", "until"))])
          c.text(times, style=if narrow { @sf.secondary.then(@sf.full_words) } else { desk_muted }) |> ignore
        })
      })
      |> ignore
    }
  })
}

///|
/// A device's name and 当前 taking what its first line leaves 退出.
// kept across runs: a value (no field of it changes)
let acc_device_head : @ui.Style = @ui.style(w=@sf.grow)

///|
/// (a device's name, narrow: as wide as it is, cut short where 当前 after it leaves it less)
// kept across runs: a value (no field of it changes)
let acc_device_narrow : @ui.TextStyle = @sf.body.then(@sf.one_line).then(@ui.text_style(w=Cut))

///|
let acc_picture : Double = @sf.identity_mark

///|
// kept across runs: a value (no field of it changes)
pub let acc_delete_words : @ui.TextStyle = @sf.body.then(@sf.bad)

///|
/// (a narrow page's foot: what takes something away, 16 over it)
// kept across runs: a value (no field of it changes)
pub let acc_narrow_foot : @ui.Style = @ui.css("w=Full pt=S4")

///|
/// Devices made up, for what is shown while they are read (devices_list in its bones): this one and two others.
fn devices_sample() -> Array[Json] {
  [(6, true), (9, false), (7, false)].mapi(fn(i, d) {
    Json::object({
      "id": Json::string("sample" + i.to_string()),
      "name": Json::string(@sf.sample_words(d.0)),
      "current": Json::boolean(d.1),
      "created_at": { "ago": Json::string(@sf.sample_words(4)) },
      "expires_at": { "until": Json::string(@sf.sample_words(4)) },
    })
  })
}
