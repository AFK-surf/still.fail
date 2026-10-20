///|
/// The process's environment (node's), to ask for what a test prints only when asked.
extern "js" fn node_env(name : String) -> String =
  #|(n) => (typeof process !== "undefined" && process.env[n]) || ""

///|
test "the controls page's draw list printed when asked (MBUI_DL_PRINT=1: scripts/render_check.sh)" {
  if node_env("MBUI_DL_PRINT") == "1" {
    println("DLBEGIN")
    println(controls_kept().drawlist())
    println("DLEND")
  }
}
