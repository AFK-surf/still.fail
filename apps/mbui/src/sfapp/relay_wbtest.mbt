///|
/// Two bots of one Slack workspace are told apart by their bots' names; a workspace with one bot is its name alone.
test "relay_workspace names a workspace's bot when it has several" {
  let claude : Json = { "id": "cl", "kind": "slack", "name": "claude", "team": "AFK AI" }
  let codex : Json = { "id": "cx", "kind": "slack", "name": "codex", "team": "AFK AI" }
  let feishu : Json = { "id": "fs", "kind": "feishu", "name": "Codex 机器人", "team": "Cue 团队" }
  let bare : Json = { "id": "lk", "kind": "lark", "name": "Codex" }
  relaying.connects = [claude, codex, feishu, bare]
  assert_eq(relay_workspace(claude), "AFK AI · claude")
  assert_eq(relay_workspace(codex), "AFK AI · codex")
  assert_eq(relay_workspace(feishu), "Cue 团队")
  assert_eq(relay_workspace(bare), "Codex")
  relaying.connects = [claude, feishu]
  assert_eq(relay_workspace(claude), "AFK AI")
  relaying.connects = []
}
