// 添加 › Slack 账号 (the core's vault/oauth.ts): the person signs in on the service's own page and their token is
// kept in their vault. Where the browser comes back to is the host's: its browser session (iOS, Android) on the app's
// own scheme, else its browser login's loopback (macOS, Windows, Linux), else (the web) the web's own page, whose core
// finishes it there. The service sends the browser to the web's /vault/oauth either way, which hands it on.

///|
/// The browser login waiting for a vault's sign-in to come back, and who to tell.
let oauth_login : Ref[(@hostapi.BrowserLogin, (String) -> Unit, (Result[String, String]) -> Unit)?] = Ref(None)

///|
/// A sign-in to `provider` as the person, into `vault` (its id, or "plain") of workspace `ws`, or for an agent's
/// request to keep one (`request`, its card's: approved with the token as it comes): `done` gets the item's
/// name once it is kept, "" where the web's own page finishes it (the browser's tab says so), or why not in the
/// person's words ("cancelled": they closed the page, nothing to say).
pub fn vault_oauth(
  ws : String,
  vault : String,
  provider : String,
  request : String,
  done : (Result[String, String]) -> Unit,
) -> Unit {
  let begin = fn(back : String, opened : (String) -> Unit, failed : () -> Unit) {
    let params : Map[String, Json] = {
      "workspace": Json::string(ws),
      "vault": Json::string(vault),
      "provider": Json::string(provider),
      "back": Json::string(back),
      "request": Json::string(request),
    }
    @core.call("vault.oauthBegin", params=Json::object(params), on_done=fn(r) {
      match r {
        Ok(ok) if str(Some(ok), "url") != "" => opened(str(Some(ok), "url"))
        Ok(_) => {
          failed()
          done(Err(""))
        }
        Err(e) => {
          failed()
          done(Err(str(Some(e), "message")))
        }
      }
    })
  }
  let complete = fn(query : String) {
    let params : Map[String, Json] = {
      "workspace": Json::string(ws),
      "query": Json::string(query),
    }
    @core.call("vault.oauthComplete", params=Json::object(params), on_done=fn(r) {
      match r {
        Ok(ok) => done(Ok(str(Some(ok), "name")))
        Err(e) if str(Some(e), "code") == "cancelled" => done(Err("cancelled"))
        Err(e) => done(Err(str(Some(e), "message")))
      }
    })
  }
  if @core.has_browser_session() {
    begin(@core.app_scheme(), fn(url) {
      let opened = @core.browser_session(url, fn(back) {
        match back {
          Ok(query) => complete(query)
          Err(why) => done(Err(if why == "cancelled" { why } else { "" }))
        }
      })
      if !opened {
        done(Err(""))
      }
    }, fn() {  })
    return
  }
  let cloud = @core.cloud()
  let finished = if cloud == "" { "" } else { cloud + "/vault/oauth?done=1" }
  match @hostapi.browser_login(path="/vault/oauth/back", done=finished) {
    Some(l) => {
      // (one begun before and not come back: given up, as this one takes its place)
      if oauth_login.val is Some((was, _, told)) {
        oauth_login.val = None
        was.end()
        told(Err("cancelled"))
      }
      begin(l.redirect, fn(url) {
        if !l.open(url) {
          @hostapi.log("No browser opened: open " + url)
        }
        oauth_login.val = Some((l, complete, done))
      }, fn() { l.end() })
    }
    // (the web: its own page finishes it, in the tab the service's page was opened in)
    None =>
      begin("web", fn(url) {
        if @ui.open_url(url) {
          done(Ok(""))
        } else {
          done(Err(""))
        }
      }, fn() {  })
  }
}

///|
/// Each frame: a vault's sign-in come back to the browser login, finished with what it brought.
fn oauth_back() -> Unit {
  guard oauth_login.val is Some((l, complete, _)) else { return }
  guard l.back() is Some(back) else { return }
  oauth_login.val = None
  l.end()
  complete(@core.query_of(back))
}
