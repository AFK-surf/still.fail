///|
/// A screen's kept draw list (src/sfscreens/__snapshot__/NAME), "" when there is none: what it is compared with
/// across machines (drawlist_same), read where the tests run (this module's root, or this package's directory).
extern "js" fn kept_drawlist(name : String) -> String =
  #|(name) => {
  #|  const fs = require("fs"), path = require("path");
  #|  for (const d of ["src/sfscreens/__snapshot__", "__snapshot__", "apps/mbui/src/sfscreens/__snapshot__"]) {
  #|    const p = path.join(process.cwd(), d, name);
  #|    if (fs.existsSync(p)) return fs.readFileSync(p, "utf8");
  #|  }
  #|  return "";
  #|}
