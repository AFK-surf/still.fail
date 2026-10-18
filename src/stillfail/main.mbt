// still.fail in mbui (docs/stillfail-port.md): the core started (src/sfcore), signed out its sign-in page, signed in
// Home (src/sfapp), over the account's own data. (The made-up chats are src/sffix's, never this app's.) A build with
// no core (the web's) says so.
//
// MBUI_CORE_DUMP=1 prints the topics Home reads as they come (DUMP <topic> …), for seeing their shapes; it changes
// nothing (no call is made).

///|
/// The topics asked for, by their key: one subscription each, asked again the same every frame.
let dumped : Map[String, Int] = {}

///|
fn core_topic(name : String, params : Map[String, Json]) -> @sfapp.Topic {
  let s = @core.subscribe(name, params~)
  if dump {
    let key = name + " " + Json::object(params).stringify()
    if dumped.get(key) != Some(s.version) {
      dumped[key] = s.version
      match (s.value, s.error) {
        (Some(v), _) => @host.log("DUMP \{key} \{v.stringify()}")
        (_, Some(e)) => @host.log("DUMP \{key} error \{e.stringify()}")
        _ => ()
      }
    }
  }
  { value: s.value, error: s.error, version: s.version }
}

///|
let dump : Bool = @host.env("MBUI_CORE_DUMP") == "1"

///|
/// People's pictures as the core gives them (`picture`): asked once each, kept as images.
let pictures : Map[String, String] = {}

///|
fn picture(url : String) -> String {
  match pictures.get(url) {
    Some(key) => key
    None => {
      pictures[url] = ""
      let params : Map[String, Json] = { "url": Json::string(url) }
      @core.call_bytes("picture", params=Json::object(params), on_done=fn(r) {
        match r {
          Ok((_, Some(bytes))) if bytes.length() > 0 => {
            let key = "mem:picture/\{url.hash()}/\{url.length()}"
            @ui.add_image(key, bytes)
            pictures[url] = key
            @host.request_frame()
          }
          _ => ()
        }
      })
      ""
    }
  }
}

///|
let core_source : @sfapp.Source = {
  topic: core_topic,
  call: fn(name, params, done) {
    @core.call(name, params~, on_done=fn(r) {
      done(r)
      @host.request_frame()
    })
  },
  sign_in: fn() { @sfcore.sign_in() },
  signing_in: fn() { @sfcore.state.busy },
  picture,
  fatal: fn() { @core.fatal() },
}

///|
fn main {
  if core_linked() == 0 || !@sfcore.start() {
    @ui.run("still.fail", fn(c) {
      @sf.begin(c) |> ignore
      c.box(w=Fill(1.0), h=Fill(1.0), align=ACenter, justify=JCenter, fn() {
        c.text("这个版本没有链接内核（APP=stillfail scripts/mac.sh build）", size=13.0, color=@sf.theme().p.muted)
        |> ignore
      })
      |> ignore
    })
    return
  }
  @ui.run("still.fail", fn(c) {
    @sfcore.frame(@core.subscribe("accounts"))
    @sfapp.view(c, core_source)
  })
}
