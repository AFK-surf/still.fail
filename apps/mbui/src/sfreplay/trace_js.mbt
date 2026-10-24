///|
/// (scripts/rerecord.sh runs the flows on JavaScript: the trace from $MBUI_APP_MOD, or up from where it runs)
extern "js" fn trace_text(name : String) -> String =
  #|(name) => {
  #|  const fs = require("fs"), path = require("path");
  #|  const rel = path.join("e2e", "traces", name + ".trace");
  #|  const dirs = [];
  #|  if (process.env.MBUI_APP_MOD) dirs.push(process.env.MBUI_APP_MOD);
  #|  for (let d = process.cwd(); ; d = path.dirname(d)) { dirs.push(d); if (path.dirname(d) === d) break; }
  #|  for (const d of dirs) { const p = path.join(d, rel); if (fs.existsSync(p)) return fs.readFileSync(p, "utf8"); }
  #|  return "\u0000";
  #|}

///|
pub fn read_trace(name : String) -> String? {
  let t = trace_text(name)
  if t == "\u0000" {
    None
  } else {
    Some(t)
  }
}
