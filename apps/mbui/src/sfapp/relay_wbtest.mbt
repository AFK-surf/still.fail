///|
/// The bot gone on through: the one picked, else the chat's own (the station's preferred), else the first; named with
/// its workspace when the bots are in several.
test "relay_bot is the chat's own bot until another is picked" {
  let claude : Json = { "id": "cl", "kind": "slack", "name": "claude", "team": "AFK AI" }
  let codex : Json = { "id": "cx", "kind": "slack", "name": "codex", "team": "AFK AI", "preferred": true }
  let feishu : Json = { "id": "fs", "kind": "feishu", "name": "Codex 机器人", "team": "Cue 团队" }
  relaying.connects = [claude, codex]
  assert_eq(relay_bot().map(fn(b) { text(Some(b), "id") }), Some("cx"))
  assert_eq(relay_bot_label(codex), "codex")
  relaying.bot = "cl"
  assert_eq(relay_bot().map(fn(b) { text(Some(b), "id") }), Some("cl"))
  relaying.bot = ""
  relaying.connects = [claude, feishu]
  assert_eq(relay_bot().map(fn(b) { text(Some(b), "id") }), Some("cl"))
  assert_eq(relay_bot_label(feishu), "Codex 机器人 · Cue 团队")
  relaying.connects = []
  assert_eq(relay_bot(), None)
}
