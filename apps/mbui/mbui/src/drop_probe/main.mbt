///|
fn main {
  @hostapi.window_setup(400.0, 300.0, 560.0, 400.0)
  let pending : @signals.Signal[(String, @ui.Pick)?] = @signals.signal(None)
  let status = @signals.signal("Drag a Finder file here")
  @signals.effect(fn() {
    match pending.get() {
      Some((destination, pick)) =>
        match pick.files() {
          Some(files) => {
            let names = files.map(fn(file) {
              @hostapi.log("READ " + destination + " " + file.name + " bytes=" + file.bytes.length().to_string())
              file.name
            })
            status.set(destination + ": " + names.join(", "))
            pending.set(None)
          }
          None => ()
        }
      None => ()
    }
  }) |> ignore
  let take = fn(destination : String, pick : @ui.Pick) {
    @hostapi.log("DROP " + destination)
    pending.set(Some((destination, pick)))
  }
  @ui.run("External files probe", fn(_) {}, tree=fn(root) {
    root.box(fn(page) {
      page.width(Is(Some(520.0))).height(Is(Some(350.0))) |> ignore
      let page_over = @ui.files_into_node(page, fn(pick) { take("outer", pick) })
      page.ground(By(fn() { if page_over() { 0xAECBE8FFL } else { 0xDCE8F2FFL } })) |> ignore
      page.box(fn(label) {
        label.offset(Is((20.0, 20.0))).words(By(fn() { status.get() })) |> ignore
      }) |> ignore
      page.box(fn(folder) {
        folder.offset(Is((160.0, 85.0))).width(Is(Some(220.0))).height(Is(Some(150.0))) |> ignore
        let folder_over = @ui.files_into_node(folder, fn(pick) { take("folder", pick) })
        folder.owns(@signals.effect(fn() { if folder_over() { @hostapi.log("HOVER folder") } })) |> ignore
        folder.ground(By(fn() { if folder_over() { 0x3BC16EFFL } else { 0x93DBACFFL } })) |> ignore
        folder.box(fn(label) { label.offset(Is((16.0, 16.0))).words(Is("Folder target")) |> ignore }) |> ignore
      }) |> ignore
    }) |> ignore
  })
}
