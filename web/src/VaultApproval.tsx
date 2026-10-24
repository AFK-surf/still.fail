// The answer to an agent's request about a vault item (docs/vault.md), at the foot of its card (VaultAsk.tsx), on the
// decisions page (奏) and on the vault's page: the answer most give as the one solid button (允许 / 存入), the other as
// words beside it (拒绝 / 不存); how long a use is allowed, a choice beside them that starts at the longest the item is
// given for. A tap asks the core (`vault.approve`, which has the system ask the person; `vault.deny`); once decided the
// station restates the card. Only the viewer's own request (the `vaults` topic's requests) is answered, and only in an
// app that keeps keys (or without security mode, anywhere); elsewhere a line says whose it is or where it is approved. A
// secret to keep while the vault is not on on this device: 开启密钥库 in the button's place, to the vault's page.
import { useState, type ReactNode } from "react";
import { useGo } from "./go.ts";
import { scopeOf } from "./station.tsx";
import { useDoingList, doingMatches, failed } from "./doing.ts";
import { type Scope, scopesUpTo, useVaultCall, useVaultRequest } from "./vault.ts";
import { Button, Chooser, ChooserItem } from "./ui.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as css from "./VaultAsk.css.ts";
import { t } from "./i18n.ts";

const scopeName = (s: Scope): string => t(`web-pages.vault.scope.${s}`);

/**
 * The answer to request `id` in `workspace`. `who`: whose it is to decide, said where it is not the viewer's.
 * `onDecided` once it went through (the decisions page sends the card on its way).
 */
export function VaultActions({ workspace, id, who, onDecided, extra }: { workspace: string; id: string; who?: string | undefined; onDecided?: (() => void) | undefined; extra?: ReactNode }) {
  const { view, request } = useVaultRequest(workspace, id);
  const run = useVaultCall();
  const go = useGo();
  const doing = useDoingList().filter((d) => !failed(d) && doingMatches(d, ["vault.approve", "vault.deny"], { workspace, request: id }));
  // What was tapped while the core has it (and the system asks the person); the use's length, once picked.
  const [pending, setPending] = useState<"yes" | "no" | null>(null);
  const [picked, setPicked] = useState<Scope | null>(null);
  if (!view) return null;
  // A web page keeps no keys (the plain library's, without security mode, are approved anywhere).
  if (!view.available && view.plain !== true) return <p className={css.note}>{t("web-pages.vault.approve.inClient")}</p>;
  if (!request) return <p className={css.note}>{who ?? t("web-pages.vault.approve.decided")}</p>;
  const save = request.save !== undefined;
  const scopes = scopesUpTo(request.lasts);
  const scope = picked ?? scopes.at(-1)!;
  const under = pending !== null || doing.length > 0;
  const busy = (yes: boolean) => pending === (yes ? "yes" : "no") || doing.some((d) => d.call === (yes ? "vault.approve" : "vault.deny"));
  const answer = (yes: boolean) => {
    if (under) return;
    setPending(yes ? "yes" : "no");
    const asked = yes
      ? run("vault.approve", { workspace, request: id, scope: save ? "once" : scope }, t(save ? "web-pages.vault.act.saveWhat" : "web-pages.vault.act.allowWhat"))
      : run("vault.deny", { workspace, request: id }, t("web-pages.vault.act.denyWhat"));
    void asked.then((v) => {
      setPending(null);
      if (v !== undefined) onDecided?.();
    });
  };
  const no = <Button variant="ghost" busy={busy(false)} disabled={under} onClick={() => answer(false)}>{t(save ? "web-pages.vault.act.dontSave" : "web-pages.vault.act.deny")}</Button>;
  // Kept only in a vault that is on here: the way to turn it on first.
  if (save && view.plain !== true && !view.setUp) {
    return <div className={pagesCss.cardFoot}><Button variant="primary" onClick={() => go(`/w/${workspace}/settings/vault`)}>{t("web-pages.vault.setUp")}</Button>{no}{extra}</div>;
  }
  return (
    <div className={pagesCss.cardFoot}>
      <Button variant="primary" busy={busy(true)} disabled={under} onClick={() => answer(true)}>{t(save ? "web-pages.vault.act.save" : "web-pages.vault.act.allow")}</Button>
      {no}
      {!save && scopes.length > 1 && (
        <Chooser label={scopeName(scope)}>
          {scopes.map((s) => <ChooserItem key={s} checked={s === scope} onSelect={() => setPicked(s)}>{scopeName(s)}</ChooserItem>)}
        </Chooser>
      )}
      {extra}
    </div>
  );
}

/** The answer under a card that names a vault request (`card.vault`), at a station's `address`. */
export function VaultCard({ address, id, who, onDecided }: { address: string; id: string; who?: string | undefined; onDecided?: (() => void) | undefined }) {
  return <VaultActions workspace={scopeOf(address)} id={id} who={who} onDecided={onDecided} />;
}
