// The device beyond the window, tried on a host (src/ui/device.mbt): a key catcher holds the focus from the start and
// says on the log what it caught ("CAUGHT …"); words typed into it ending in "!" are commands: paste! reads the
// clipboard ("CLIP …"), copytext! and copypng! write it (a one-pixel PNG), awake! and sleep! keep the screen on or let
// it go, haptic! fires a long press's. The soft keyboard's height is said as it changes ("IME …"). The last line said is
// on the screen too, for a scripted run's `until`: `APP=devicedemo scripts/android.sh build`, scripts/mac.sh.

///|
/// A PNG of one pixel.
let pixel_png : Bytes = b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\rIDATx\x9cc\xf8\xcf\xc0\xf0\x1f\x00\x05\x00\x01\xff\x89\x99=\x1d\x00\x00\x00\x00IEND\xaeB`\x82"

///|
fn picture_said(p : @ui.ClipPicture) -> String {
  match p {
    NoPicture => "none"
    Png(b) => "png \{b.length()} " + (if b == pixel_png { "same" } else { "other" })
    TooLarge => "too large"
    Unreadable => "unreadable"
  }
}

///|
fn main {
  let last = Ref::new("ready")
  let typed = StringBuilder::new()
  let read : Ref[@ui.ClipboardRead?] = Ref::new(None)
  let inset = Ref::new(-1.0)
  let say = fn(s : String) {
    @ui.log(s)
    last.val = s
  }
  let command = fn(typed : String) {
    // (what was typed before it, with no space between, is not the command's)
    let commands = ["paste", "copytext", "copypng", "awake", "sleep", "haptic"]
    let word = match commands.search_by(fn(w) { typed.has_suffix(w) }) {
      Some(i) => commands[i]
      None => typed
    }
    match word {
      "paste" => read.val = @ui.clipboard_read()
      "copytext" => @ui.clipboard_set("copied words", label="devicedemo")
      "copypng" => @ui.clipboard_set_png(pixel_png, label="devicedemo")
      "awake" => @ui.keep_awake(true)
      "sleep" => @ui.keep_awake(false)
      "haptic" => @ui.haptic(LongPress)
      _ => ()
    }
    say("DONE \{word} (copy shown: \{@ui.copy_shown()})")
  }
  @ui.run("devicedemo", fn(c) {
    c.catch_keys("keys", true)
    let k = c.key_catcher("keys")
    if k.keys.length() > 0 {
      let keys = k.keys
      c.tell("caught", fn() {
        for key in keys {
          say("CAUGHT \{key}")
          match key {
            Text(s) =>
              for ch in s {
                if ch == '!' {
                  let word = typed.to_string()
                  typed.reset()
                  command(word)
                } else if ch == ' ' {
                  typed.reset()
                } else {
                  typed.write_char(ch)
                }
              }
            _ => ()
          }
        }
      })
    }
    let h = c.ime_inset()
    if h != inset.val {
      c.tell("inset", fn() {
        inset.val = h
        say("IME \{h}")
      })
    }
    match read.val {
      Some(r) =>
        match r.got() {
          Some(clip) => {
            read.val = None
            // (shown by this frame: taken once, in its first build)
            let line = "CLIP text=\{clip.text} picture=\{picture_said(clip.picture)}"
            last.val = line
            c.tell("clip", fn() { @ui.log(line) })
          }
          None => ()
        }
      None => ()
    }
    c.column(fn() {
      c.text(if k.focused { "typing" } else { "idle" }) |> ignore
      c.text(last.val) |> ignore
    })
    |> ignore
  })
}
