// The desktop's 账号 (web/src/cloud/settings.tsx AccountSettings) on the library's parts: who is signed in (its picture,
// name, email and how it signs in), where it is signed in (each device, signed out from here but this one), signing out
// here, deleting the account; each asked first.

///|
/// 账号 (AccountSettings).
fn me_page(c : @ui.Ctx, core : Core, here : Here) -> Unit {
  let name = if here.person != "" { here.person } else { here.email }
  let how = if here.sub.has_prefix("em-") || here.sub.has_prefix("pw-") {
    @sf.t("web-pages.settings.account.email")
  } else {
    @sf.t("web-pages.settings.account.google")
  }
  desk_page(
    c,
    core,
    "me",
    @sf.t("android-settings.me.title"),
    // who it is (identity): its picture 52, its name in the heading's size, its email and how it signs in under it
    head=fn() {
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
    },
    [
      fn() {
        @sf.section(c, @sf.t("web-pages.settings.account.sessions"), note=@sf.t("web-pages.settings.account.sessionsLead", args=[("name", "still.fail")]), fn() {
          acc_devices(c, core, here)
        })
      },
      fn() {
        @sf.section(c, @sf.t("web-pages.settings.account.signOut"), fn() {
          c.box(style=desk_card, fn() {
            c.box(style=desk_card_row, fn() {
              c.box(style=desk_card_text, fn() {
                c.text(@sf.t("web-pages.settings.account.signOutHere", args=[("email", here.email)]), style=desk_strong) |> ignore
                c.text(@sf.t("web-pages.settings.account.signOutHereBody"), style=desk_muted) |> ignore
              })
              |> ignore
              if @sf.button(c, @sf.t("web-pages.settings.account.signOutAction"), key="account-sign-out", icon="log-out") {
                confirm(
                  @sf.t("web-pages.settings.account.signOutConfirm", args=[("email", here.email)]),
                  @sf.t("web-pages.settings.account.signOutConfirmBody"),
                  @sf.t("web-pages.settings.account.signOutAction"),
                  fn() {
                    (core.home)()
                    @settings.act(
                      core,
                      @sf.t("web-pages.settings.account.signOut"),
                      "auth.signOut",
                      obj([("account", str(here.sub))]),
                      done=@sf.t("web-pages.settings.account.signedOut", args=[("email", here.email)]),
                    )
                  },
                )
              }
            })
            |> ignore
          })
          |> ignore
        })
      },
      fn() {
        @sf.section(c, @sf.t("web-pages.settings.account.delete"), fn() {
          c.box(style=desk_card, fn() {
            c.box(style=desk_card_row, fn() {
              c.box(style=desk_card_text, fn() {
                c.text(@sf.t("web-pages.settings.account.deleteHere", args=[("email", here.email)]), style=desk_strong) |> ignore
                c.text(@sf.t("web-pages.settings.account.deleteHereBody", args=[("name", "still.fail")]), style=desk_muted) |> ignore
              })
              |> ignore
              if @sf.button(c, @sf.t("web-pages.settings.account.deleteAction"), key="account-delete", tone=Danger, icon="trash") {
                confirm(
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
            })
            |> ignore
          })
          |> ignore
        })
      },
    ],
  )
}

///|
/// Where the account is signed in (the `loginSessions` topic): each device's name (this one marked 当前), when it signed
/// in and until when; 退出 on the others (`loginSession.revoke`).
fn acc_devices(c : @ui.Ctx, core : Core, here : Here) -> Unit {
  let topic = (core.topic)("loginSessions", { "account": str(here.sub) })
  let list = match topic.value {
    Some(Array(a)) => a
    _ => {
      match topic.error {
        Some(e) =>
          c.text(@sf.t("web-pages.settings.account.sessionsFailed", args=[("error", error_text(e))]), style=desk_note_bad) |> ignore
        None => @sf.wait_line(c, @sf.t("common.reading"))
      }
      return
    }
  }
  c.box(style=desk_list, fn() {
    for d in list {
      let dv = Some(d)
      let id = text(dv, "id")
      let current = flag(dv, "current")
      c.box(style=desk_list_row, fn() {
        c.box(style=desk_list_text, fn() {
          c.box(style=desk_named, fn() {
            c.text(
              match text(dv, "name") {
                "" => @sf.t("web-pages.settings.account.unnamedDevice")
                n => n
              },
              style=desk_list_title,
            )
            |> ignore
            if current {
              you(c, @sf.t("web-pages.settings.account.here"))
            }
          })
          |> ignore
          c.text(
            @sf.t("web-pages.settings.account.sessionTimes", args=[("time", stamp(dv, "created_at", "ago")), ("until", stamp(dv, "expires_at", "until"))]),
            style=desk_muted,
          )
          |> ignore
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
  |> ignore
}

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
