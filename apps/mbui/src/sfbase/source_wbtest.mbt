// The app asks the core for only the chat data its page uses, while other topics keep their own parameters.

///|
test "a chat asks the core for a compact view" {
  let params : Map[String, Json] = { "station": "w/s", "session": "k" }
  let chat = core_topic_params("chat", params)
  assert_eq(chat.get("compact"), Some(Json::boolean(true)))
  assert_eq(chat.get("session"), Some(Json::string("k")))
  assert_true(params.get("compact") is None)
  assert_eq(core_topic_params("chatJobs", params).get("compact"), Some(Json::boolean(true)))
  assert_eq(core_topic_params("history", params).get("compact"), None)
}
