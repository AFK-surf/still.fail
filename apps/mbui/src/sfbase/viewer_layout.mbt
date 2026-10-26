// What the viewer lays out as the web's (ember web/src/FilePreview.tsx, FilePreview.css.ts), read by its stages
// (viewer.mbt), and how it says where a file was opened from.

///|
/// Back to where it was opened from, by name (FilePreview.tsx backLabel): a drive's file its folder (mobile/Drive.tsx
/// DrivePreview), a chat's its chat's title; 关闭 when neither is known.
pub fn Viewer::desk_back(self : Viewer, src : Source) -> String {
  match self.drive {
    Some(d) => viewer_folder_label(src, d.station, d.root, dv_parent(d.path))
    None => {
      let title = text((src.topic)("chat", { "station": Json::string(self.station), "session": Json::string(self.key) }).value, "title")
      if title != "" {
        title
      } else {
        @sf.t("common.close")
      }
    }
  }
}

///|
/// A folder of a station's drive by name (drive/Drive.tsx useOpened `back`): its last part, the folder lent by its
/// name at its root.
pub fn viewer_folder_label(src : Source, station : String, root : String, folder : String) -> String {
  if folder != "" {
    return dv_name(folder)
  }
  let ws = match station.find("/") {
    Some(i) => station.view(end_offset=i).to_owned()
    None => station
  }
  let roots = match dv_stations(src, ws).0 {
    Some(list) =>
      match list.iter().find_first(fn(s) { s.station == station }) {
        Some(s) => s.roots
        None => []
      }
    None => []
  }
  dv_root_label(roots, root)
}

///|
/// How a PDF's pages lie on a desktop (FilePreview.css.ts fpPdf): as wide as 1000 allows less 28 either side, 76 under
/// the window's top, 20 apart, 28 at the foot.
pub fn desk_pdf_width(window : Double) -> Double {
  dmax(0.0, dmin(desk_pdf_most, window) - 2.0 * desk_pdf_side)
}

///|
pub let desk_pdf_most : Double = 1000.0

///|
pub let desk_pdf_side : Double = 28.0

///|
/// Down to where a document starts under the bar (fpPdf, fpPlain, fpPageFrame: 76; a table's head, fpTableWrap: 68).
pub let desk_page_top : Double = 76.0

///|
pub let desk_table_top : Double = 68.0

///|
/// How far the system's status bar reaches over the window (a tablet's), where the bar is across the top (not laid
/// out Small, whose bar floats: @sf.viewer_frame_bar): what a document under it starts that much lower for.
fn viewer_top(c : @ui.Ctx) -> Double {
  if @sf.layout(c.width) is Small {
    0.0
  } else {
    (@sf.viewer_host().room)().0
  }
}

///|
/// How far the system's navigation bar reaches over the window's foot, as viewer_top.
fn viewer_foot(c : @ui.Ctx) -> Double {
  if @sf.layout(c.width) is Small {
    0.0
  } else {
    (@sf.viewer_host().room)().1
  }
}

///|
pub let desk_pdf_gap : Double = 20.0

///|
pub let desk_pdf_foot : Double = 28.0

///|
/// A table's words (fpTable: --text-ui, 13).
pub let desk_cell_size : Double = 13.0

///|
/// The wheel's zoom (useZoom onWheel): a pinch's small steps (under 50) by a hundredth of each, a wheel's notches by a
/// five-hundredth.
pub let desk_pinch_step : Double = 50.0

///|
pub let desk_pinch_rate : Double = 0.01

///|
pub let desk_wheel_rate : Double = 0.002

///|
/// Code and plain text (fpCode, fpPlain): 12 on 1.6 (code) or 1.65, 32 in, 64 at the foot.
pub let desk_code_size : Double = 12.0

///|
pub let desk_code_line : Double = 19.2

///|
pub let desk_plain_line : Double = 19.8

///|
pub let desk_text_side : Double = 32.0

///|
pub let desk_text_foot : Double = 64.0

///|
/// As it is (a zoom of 1).
pub let desk_whole : Double = 1.0


///|
/// Under 640 (FilePreview.css.ts's phone widths): a page and a PDF 60 down, a PDF's pages 12 in and apart, a text 16 in
/// and 48 under.
pub let page_small_top : Double = 60.0

///|
pub let pdf_small_in : Double = 12.0

///|
pub let plain_small_side : Double = 16.0

///|
pub let plain_small_foot : Double = 48.0
