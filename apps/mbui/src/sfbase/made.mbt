// What a made-up core (src/sffixture: a test's, a tool's) keeps beside the app, put back and told as the app runs: wires
// it sets as it is linked; nothing where none is.

///|
/// The made-up core's own put back with the app's (its reset).
// kept across runs: a wire, said once as the made-up core is linked
pub let made_reset : Ref[() -> Unit] = Ref(fn() {  })

///|
/// Each frame's Ctx told the made-up core (its timers run on the frames' runtime once there is one).
// kept across runs: a wire, said once as the made-up core is linked
pub let made_frame : Ref[(@ui.Ctx) -> Unit] = Ref(fn(_) {  })

///|
/// What a made-up core says of a station's screen (`screen.view`) for the fixture's mode: the screen's page's own
/// (sfpages' screen_fixture.mbt, its states and frames kept with the page until they are the made-up core's), given
/// as the app starts.
// kept across runs: a wire, said once as the app starts
pub let screen_made_stream : Ref[(Json, (Json, Bytes?) -> Unit, (Result[Json, Json]) -> Unit) -> Int] = Ref(fn(_, _, done) {
  done(Err({ "code": "unknown_call", "message": "no screen made up" }))
  0
})
