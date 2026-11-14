// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `linkPreview page` whole on a
// workspace of real size.
///|
fn init {
  let asked =
    #|{"topic":"linkPreview","station":"ws/maple","url":"https://www.anthropic.com/news/claude-opus-5-5"}
  let value =
    #|{"kind":"page","url":"https://www.anthropic.com/news/claude-opus-5-5","title":"Introducing Claude Opus 5.5","description":"Our most capable model yet for coding, agents and long-running work, with a context window of a million tokens and better judgment about when to ask.","site":"Anthropic","icon":"wxzhni4wqr-6c6","image":"1plggwk0nc8-4okv"}
  put(asked, value)
}
