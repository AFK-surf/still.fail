// Claude's authorization page is opened only after the person confirms, whichever browser opens it.

///|
pub fn confirm_claude_auth(claude : Bool, open : () -> Unit) -> Unit {
  if claude {
    @sf.confirm(
      @sf.t("common.login.confirmClaudeTitle"),
      @sf.t("common.login.confirmClaudeBody"),
      @sf.t("common.login.confirmClaudeAction"),
      open,
    )
  } else {
    open()
  }
}
