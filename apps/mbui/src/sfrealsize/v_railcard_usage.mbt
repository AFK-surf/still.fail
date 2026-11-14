// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `railCard usage` whole on a
// workspace of real size.
///|
fn init {
  let asked =
    #|{"topic":"railCard","scope":"ws","place":"usage"}
  let value =
    #|{"head":"近 7 天折合 $7,964","stats":[{"value":"$939","label":"今天"},{"value":"7.7 亿","label":"输入 token"}],"rows":[{"name":"Sonnet 5","value":"$1,393 · 17%"},{"name":"Sonnet 4.5","value":"$1,359 · 17%"},{"name":"Fable 1","value":"$1,291 · 16%"}],"days":[{"label":"9/30","share":0.98809303473379,"today":false},{"label":"10/1","share":0.7689555185390834,"today":false},{"label":"10/2","share":1,"today":false},{"label":"10/3","share":0.8559750755752978,"today":false},{"label":"10/4","share":0.8620210993892283,"today":false},{"label":"10/5","share":0.9430254796717874,"today":false},{"label":"10/6","share":0.7238879634770807,"today":true}],"share":true}
  put(asked, value)
}
