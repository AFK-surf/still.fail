// An agent's request about a vault item where its card is (VaultAsk.tsx, VaultApproval.tsx): to use one or to keep one
// (docs/vault.md 申请和授权, agent 存入). In place of the post's words, the request's card (the settings', the vault
// page's too: settings/vault_ask.mbt); once decided, one line saying how it ended.

///|
/// The card in place of an agent's post asking about a vault item (`card.vaultAsk`), at the chat's station.
fn vault_ask_card(c : @ui.Ctx, src : Source, here : Here, card : Card, ask : VaultAsk) -> Unit {
  let asked : @settings.Asked = {
    name: ask.name,
    mode: ask.mode,
    command: ask.command,
    save_kind: ask.save_kind,
    username: ask.username,
    station: ask.station,
  }
  if ask.status != "" {
    @settings.vault_outcome(c, asked, ask.status, ask.scope)
    return
  }
  let ws = workspace_of(here.station)
  let me = here.view.me
  let mine = card.assignee == "" || me == "" || card.assignee.to_lower() == me.to_lower()
  @settings.vault_ask(c, vault_core(src, ws), ws, card.vault, asked, mine, who=card.assignee_text)
}

///|
/// The answer under a card that names a vault request but says nothing of it (from a station before `vaultAsk`), and
/// on the 奏 page under such a post: the buttons alone.
fn vault_approval(c : @ui.Ctx, src : Source, ws : String, request : String, mine : Bool) -> Unit {
  @settings.vault_actions(c, vault_core(src, ws), ws, request, mine)
}

///|
/// The core as the settings' pages have it, over workspace `ws` (its name not needed here).
fn vault_core(src : Source, ws : String) -> @settings.Core {
  settings_core(src, { id: ws, name: "", emoji: "", icon: "", email: "" })
}
