// An agent's request about a vault item where its card is (VaultAsk.tsx, VaultApproval.tsx): to use one or to keep one
// (docs/vault.md 申请和授权, agent 存入). In place of the post's words, the request's card is sfpages' (decision.mbt
// vault_ask_card); here the answer under a card from before its station said what it asks.

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
