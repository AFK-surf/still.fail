///|
/// The real core's answers to its pure calls, kept (src/sfkept): these tests have no core.
fn init {
  @sf.kept_call.val = Some(@sfkept.answer)
}
