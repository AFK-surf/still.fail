// Files let go on the window from outside are taken by the box there and read (scripts/host_contract.sh linux dropped):
// on a real host, MBUI_DROPCHECK=1 with a drive script's `drop X Y PATH|…` (the host's own drop: Linux's drop_drive,
// the way its GTK drop target goes). The window is one box that takes files (Ctx::on_files); what it is given, its
// pick read once taken (a folder's by their way down, each folder named with a "/" at its end), is said on the log in
// String's order (shorter first) with how many bytes they hold (`DROPCHECK taken N: name,name… (B bytes)`) and shown (`dropped N`, what
// the script waits for before it ends the run).

///|
/// What was read, shown once it is (`dropped N`)
// kept across runs: the run's one check
let drop_check_shown : @signals.Signal[String] = @signals.signal("")

///|
/// The window whole, what files are let go on
// kept across runs: a style, the same every run
let drop_check_whole : @ui.Style = @ui.css("w=Full h=Full")

///|
pub fn drop_check_run(c : @ui.Ctx) -> Unit {
  let id = c.id("drop-check")
  c.takes_presses(id)
  c.on_files(id, held=fn(_) {  }, take=fn(_, _) {
    Some(fn(p) {
      @hostapi.log("DROPCHECK taken as files")
      @signals.effect(fn() {
        match p.files() {
          Some(files) => {
            let names = files.map(fn(f) { f.name })
            names.sort()
            let bytes = files.fold(init=0, fn(n, f) { n + f.bytes.length() })
            @hostapi.log("DROPCHECK taken \{names.length()}: \{names.join(",")} (\{bytes} bytes)")
            drop_check_shown.set("dropped \{names.length()}")
          }
          None => ()
        }
      })
      |> ignore
    })
  })
  c.box(id~, style=drop_check_whole, fn() {
    c.text(if drop_check_shown.get() == "" { "drop check" } else { drop_check_shown.get() }) |> ignore
  })
  |> ignore
}
