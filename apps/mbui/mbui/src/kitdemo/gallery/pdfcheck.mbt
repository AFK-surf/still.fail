// The PDFs' contract (scripts/host_contract.sh HOST pdf): on a real host, MBUI_PDFCHECK=<a PDF's bytes, base64>
// (test/host/pdfcheck.pdf: two pages of 200 × 100 points, red on the left half and blue on the right, the second turned
// a quarter clockwise by its /Rotate): its pages and their sizes as the host reads them (`PDFCHECK pages 2 200x100
// 100x200`), then each page drawn at most 400 pixels on its longer side: its size, and its colours a quarter of the way
// in from either end of that side (`PDFCHECK page 0 400x200 ff0000 0000ff`), then the app's end. `PDFCHECK none` where
// the host draws no PDF. The host asks for a frame as each page is drawn: each frame's build only asks whether it is.

///|
let pdf_check_doc : Ref[Int] = Ref(0)

///|
/// each page's image, as asked for
let pdf_check_images : Ref[Array[Int]] = Ref([])

///|
/// how many pages are said
let pdf_check_said : Ref[Int] = Ref(0)

///|
fn pdf_check_hex(px : FixedArray[Byte], at : Int) -> String {
  let digits = "0123456789abcdef".to_array()
  let out = StringBuilder()
  for i in 0..<3 {
    let b = px[at + i].to_int()
    out.write_char(digits[b / 16])
    out.write_char(digits[b % 16])
  }
  out.to_string()
}

///|
/// What the check does each frame, once its builds are over: the PDF opened and its pages asked for (the first time),
/// then each page as it is drawn, in order, and the app's end.
fn pdf_check_step(pdf : String) -> Unit {
  if pdf_check_doc.val == 0 {
    let doc = @hostapi.pdf_open(@codec.from_base64(pdf))
    let pages = if doc == 0 { -1 } else { @hostapi.pdf_pages(doc) }
    if pages < 0 {
      @hostapi.log("PDFCHECK none")
      @hostapi.exit(1)
      return
    }
    pdf_check_doc.val = doc
    let size = FixedArray::make(2, 0.0)
    let line = StringBuilder()
    line.write_string("PDFCHECK pages \{pages}")
    for p in 0..<pages {
      @hostapi.pdf_page_size(doc, p, size)
      line.write_string(" \{size[0].round().to_int()}x\{size[1].round().to_int()}")
      pdf_check_images.val.push(@hostapi.pdf_page_load(doc, p, 400))
    }
    @hostapi.log(line.to_string())
  }
  let info = FixedArray::make(4, 0.0)
  while pdf_check_said.val < pdf_check_images.val.length() {
    let p = pdf_check_said.val
    let id = pdf_check_images.val[p]
    let state = @hostapi.image_info(id, info)
    if state == 0 {
      break
    }
    if state < 0 {
      @hostapi.log("PDFCHECK page \{p} not drawn")
      @hostapi.exit(1)
      return
    }
    let w = info[0].to_int()
    let h = info[1].to_int()
    let px = FixedArray::make(w * h * 4, b'\x00')
    if !@hostapi.image_pixels(id, px) {
      @hostapi.log("PDFCHECK page \{p} \{w}x\{h} not read")
      @hostapi.exit(1)
      return
    }
    // a quarter of the way in from either end of its longer side, across its middle
    let (a, b) = if w >= h {
      (((h / 2) * w + w / 4) * 4, ((h / 2) * w + w * 3 / 4) * 4)
    } else {
      (((h / 4) * w + w / 2) * 4, ((h * 3 / 4) * w + w / 2) * 4)
    }
    @hostapi.log("PDFCHECK page \{p} \{w}x\{h} \{pdf_check_hex(px, a)} \{pdf_check_hex(px, b)}")
    pdf_check_said.val = p + 1
  }
  if pdf_check_said.val == pdf_check_images.val.length() {
    @hostapi.exit(0)
  }
}

///|
pub fn pdf_check_run(c : @ui.Ctx, pdf : String) -> Unit {
  c.after_build("pdf-check", fn() { pdf_check_step(pdf) })
  c.text("pdf check") |> ignore
}
