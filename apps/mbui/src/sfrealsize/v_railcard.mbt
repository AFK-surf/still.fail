// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `railCard` whole on a
// workspace of real size.
///|
fn init {
  let asked =
    #|{"topic":"railCard","scope":"ws","place":"chats"}
  let value =
    #|{"head":"51 个对话正在运行","stats":[{"value":"85","label":"等你处理","tone":"amber","go":"attention"},{"value":"0","label":"出错","go":"attention"},{"value":"38","label":"未读","go":"attention"},{"value":"0","label":"今天归档","go":"archive"}],"rows":[],"days":null,"share":null}
  put(asked, value)
}
