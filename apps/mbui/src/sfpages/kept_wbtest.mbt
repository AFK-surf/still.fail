///|
/// The real core's answers to its pure calls, kept (src/sfkept): this package's tests have no core (a station's prices
/// read as a table, as the app's core reads them).
fn init {
  @sf.kept_call.val = Some(@sfkept.answer)
}
