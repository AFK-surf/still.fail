// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `live` whole on a
// workspace of real size.
///|
fn init {
  let asked =
    #|{"topic":"live","station":"ws/maple","key":"k-maple-0"}
  let value =
    #|{"activity":{"now":{"key":"think","text":"思考中","mono":null,"important":null}}}
  put(asked, value)
}
