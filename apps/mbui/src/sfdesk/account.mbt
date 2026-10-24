// 账号, one page in every frame (web/src/cloud/settings.tsx AccountSettings; the narrow app's mobile/Me.tsx), laid out by
// its width (page_look.mbt): who is signed in (its picture, name, email and how it signs in), the other accounts on
// this device (each signed out of by itself) and another added, where it is signed in (each device, signed out from
// here but this one), signing out here, deleting the account; signing out and deleting asked first (@sf.confirm).

///|
/// 账号 (AccountSettings, MeScreen).
fn me_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame) -> Unit {
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
  let identity = fn() {
    match look {
      Wide =>
        c.box(style=acc_identity, fn() {
          avatar(c, core, here.email, name, acc_picture, picture=here.picture)
          c.box(style=acc_identity_text, fn() {
            c.text(name, style=acc_name) |> ignore
            c.box(style=acc_sub, fn() {
              c.text(here.email, style=acc_sub_words) |> ignore
              c.text(how, style=acc_sub_words) |> ignore
            })
            |> ignore
          })
          |> ignore
        })
        |> ignore
      // (narrow: as wide as the row leaves it, its email and how it signs in in a line cut short)
      Narrow =>
        c.box(style=acc_identity_narrow, fn() {
          avatar(c, core, here.email, name, acc_picture_narrow, picture=here.picture)
          c.box(style=acc_identity_text, fn() {
            c.text(name, style=acc_name_narrow) |> ignore
            c.text(here.email + " · " + how, style=acc_sub_narrow) |> ignore
          })
          |> ignore
        })
        |> ignore
    }
  }
  let blocks : Array[() -> Unit] = []
  match look {
    // the accounts on this device on one card (Me.tsx): the one in view with who it is, then the others, each signed
    // out of by itself, another added
    Narrow =>
      blocks.push(fn() {
        look_group(c, look, fn() {
          c.box(style=narrow_said_row, fn() {
            c.box(style=narrow_row_words, identity) |> ignore
            if acc_sign_out_link(c, "sign-out/" + here.sub, if others.length() > 0 { @sf.t("android-settings.me.signOut") } else { @sf.t("android-settings.me.signOutOnly") }) {
              sign_out(here.sub, here.email)
            }
          })
          |> ignore
          for a in others {
            let sub = text(Some(a), "sub")
            let email = text(Some(a), "email")
            c.box(style=narrow_said_row, fn() {
              c.text(email, style=narrow_row_title) |> ignore
              if acc_sign_out_link(c, "sign-out/" + sub, @sf.t("android-settings.me.signOut")) {
                sign_out(sub, email)
              }
            })
            |> ignore
          }
          if look_link(c, look, "add-account", @sf.t("android-settings.me.addAccount"), chevron=false) {
            (core.sign_in)()
          }
        })
      })
    Wide => ()
  }
  blocks.push(fn() {
    look_section(c, look, @sf.t("web-pages.settings.account.sessions"), heads=true, note=if look == Wide { @sf.t("web-pages.settings.account.sessionsLead", args=[("name", "still.fail")]) } else { "" }, fn() {
      acc_devices(c, core, look, here)
    })
  })
  match look {
    Wide => {
      // the other accounts on this device, each signed out of by itself, another added
      blocks.push(fn() {
        @sf.section(c, @sf.t("android-settings.me.accounts"), fn() {
          c.box(style=desk_list, fn() {
            for a in others {
              let sub = text(Some(a), "sub")
              let email = text(Some(a), "email")
              c.box(style=desk_list_row, fn() {
                c.box(style=desk_list_text, fn() { c.text(email, style=desk_list_title) |> ignore }) |> ignore
                if @sf.button(c, @sf.t("web-pages.settings.account.signOutAction"), key="sign-out/" + sub, tone=Ghost) {
                  sign_out(sub, email)
                }
              })
              |> ignore
            }
            if look_link(c, look, "add-account", @sf.t("android-settings.me.addAccount"), chevron=false) {
              (core.sign_in)()
            }
          })
          |> ignore
        })
      })
      blocks.push(fn() {
        @sf.section(c, @sf.t("web-pages.settings.account.signOut"), fn() {
          c.box(style=desk_card, fn() {
            c.box(style=desk_card_row, fn() {
              c.box(style=desk_card_text, fn() {
                c.text(@sf.t("web-pages.settings.account.signOutHere", args=[("email", here.email)]), style=desk_strong) |> ignore
                c.text(@sf.t("web-pages.settings.account.signOutHereBody"), style=desk_muted) |> ignore
              })
              |> ignore
              if @sf.button(c, @sf.t("web-pages.settings.account.signOutAction"), key="account-sign-out", icon="log-out") {
                sign_out(here.sub, here.email)
              }
            })
            |> ignore
          })
          |> ignore
        })
      })
      blocks.push(fn() {
        @sf.section(c, @sf.t("web-pages.settings.account.delete"), fn() {
          c.box(style=desk_card, fn() {
            c.box(style=desk_card_row, fn() {
              c.box(style=desk_card_text, fn() {
                c.text(@sf.t("web-pages.settings.account.deleteHere", args=[("email", here.email)]), style=desk_strong) |> ignore
                c.text(@sf.t("web-pages.settings.account.deleteHereBody", args=[("name", "still.fail")]), style=desk_muted) |> ignore
              })
              |> ignore
              if @sf.button(c, @sf.t("web-pages.settings.account.deleteAction"), key="account-delete", tone=Danger, icon="trash") {
                delete()
              }
            })
            |> ignore
          })
          |> ignore
        })
      })
    }
    // deleting the account in view, at the foot, in red (Me.tsx)
    Narrow =>
      blocks.push(fn() {
        c.box(style=acc_narrow_foot, fn() {
          look_group(c, look, fn() {
            let id = c.id("delete-account")
            c.cursor(id, Hand)
            if c.clicked(id) {
              delete()
            }
            let b = c.box(style=narrow_row, id~, fn() {
              c.text(@sf.t("android-settings.me.delete"), style=acc_delete_words) |> ignore
              finger_ripple(c, id)
            })
            c.semantics(b, Button, id~, label=@sf.t("android-settings.me.delete"))
          })
        })
        |> ignore
      })
  }
  look_page(
    c,
    core,
    frame,
    look,
    "me",
    @sf.t("android-settings.me.title"),
    head?=if look == Wide { Some(identity) } else { None },
    blocks,
  )
}

///|
/// 退出登录 at an account's row's end, in red: pressed, asked first.
fn acc_sign_out_link(c : @ui.Ctx, key : String, words : String) -> Bool {
  let t = @sf.theme()
  tap_text(c, key, words, color=t.p.red)
}

///|
/// Where the account is signed in (the `loginSessions` topic): each device's name (this one marked 当前), when it signed
/// in and until when; 退出 on the others (`loginSession.revoke`). Narrow, on a card.
fn acc_devices(c : @ui.Ctx, core : Core, look : Look, here : Here) -> Unit {
  let topic = (core.topic)("loginSessions", { "account": str(here.sub) })
  let list = match topic.value {
    Some(Array(a)) => a
    _ => {
      match topic.error {
        Some(e) => look_note(c, look, @sf.t("web-pages.settings.account.sessionsFailed", args=[("error", error_text(e))]), bad=true)
        None => @sf.wait_line(c, @sf.t("common.reading"))
      }
      return
    }
  }
  let narrow = look == Narrow
  look_group(c, look, fn() {
    for d in list {
      let dv = Some(d)
      let id = text(dv, "id")
      let current = flag(dv, "current")
      c.box(style=if narrow { narrow_said_row } else { desk_list_row }, fn() {
        c.box(style=desk_list_text, fn() {
          c.box(style=desk_named, fn() {
            c.text(
              match text(dv, "name") {
                "" => @sf.t("web-pages.settings.account.unnamedDevice")
                n => n
              },
              style=if narrow { narrow_row_title } else { desk_list_title },
            )
            |> ignore
            if current && !narrow {
              you(c, @sf.t("web-pages.settings.account.here"))
            }
          })
          |> ignore
          let times = @sf.t("web-pages.settings.account.sessionTimes", args=[("time", stamp(dv, "created_at", "ago")), ("until", stamp(dv, "expires_at", "until"))])
          if narrow {
            // (narrow: 当前 before its times, clear of the card's corner)
            c.box(style=acc_times_line, fn() {
              if current {
                you(c, @sf.t("web-pages.settings.account.here"))
              }
              c.text(times, style=acc_times_narrow) |> ignore
            })
            |> ignore
          } else {
            c.text(times, style=desk_muted) |> ignore
          }
        })
        |> ignore
        if !current {
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
        }
      })
      |> ignore
    }
  })
}

///|
let acc_picture_narrow : Double = 46.0

///|
// kept across runs: a value (no field of it changes)
let acc_times_narrow : @ui.TextStyle = @sf.secondary.then(@ui.text_style(w=@sf.grow))

///|
// kept across runs: a value (no field of it changes)
let acc_times_line : @ui.Style = @ui.css("row w=Full gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let acc_identity_narrow : @ui.Style = @ui.css("row w=Full gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let acc_sub_narrow : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let acc_name_narrow : @ui.TextStyle = @ui.text_style(size=Xl, weight=Bold, color=Fg, wrap=false, w=Cut)

///|
/// (the narrow page's foot: deleting, 16 over it)
// kept across runs: a value (no field of it changes)
let acc_narrow_foot : @ui.Style = @ui.css("w=Full pt=S4")

///|
// kept across runs: a value (no field of it changes)
let acc_delete_words : @ui.TextStyle = @sf.body.then(@sf.bad)

///|
let acc_picture : Double = 52.0

///|
/// (identity: its picture and its words 16 apart, 28 over what follows: 12 and the first block's own 16)
// kept across runs: a value (no field of it changes)
let acc_identity : @ui.Style = @ui.css("row w=Full gap=S4 mb=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let acc_identity_text : @ui.Style = @ui.style(w=@sf.grow, gap=S1_5)

///|
/// (identityName: the heading's size, 600)
// kept across runs: a value (no field of it changes)
let acc_name : @ui.TextStyle = @ui.text_style(size=Xl3, leading=L8, weight=Semibold, color=Fg, wrap=false)

///|
/// (identitySub: its parts 14 apart, the list's words, muted)
// kept across runs: a value (no field of it changes)
let acc_sub : @ui.Style = @ui.css("row gap=S3_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let acc_sub_words : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Muted, wrap=false)
