// The waiting page and its pairing steps share the same retained nodes with Settings › Security.

///|
pub fn lock_wait_page_node(parent : @view.View, core : Core, here : () -> @settings.Here) -> Unit {
  @sf.waiting_page_node(
    parent,
    "shield-check",
    fn() { @sf.t("web-pages.security.waitingTitle") },
    fn() { @sf.t("web-pages.security.waitingLead", args=[("name", here().name)]) },
    fn(col) { pair_steps_node(col, fn() { core }, fn() { here().workspace }) },
  )
}
