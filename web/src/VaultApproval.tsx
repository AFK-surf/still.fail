// An agent's request to use a vault item (docs/vault.md 申请和授权): under the agent's post in its chat, on the
// decisions page (奏) and on the vault's page, in place of the card's options. Rows as a decision's options are drawn
// (Decisions.css.ts): 仅本次 (`once`), 本对话 1 小时内 (`hour`), 本对话直到归档 (`chat`), as far as the item allows
// (`lasts`), the longest recommended; then 拒绝. A tap asks the core
// (`vault.approve`, which has the system ask the person; `vault.deny`); once decided the station takes the card back.
// Only the request's own (the `vaults` topic's requests: one waiting on the viewer) can be answered, and only in an app
// that keeps keys: a web page shows no rows, only that it is approved in a client (desktop or Android); elsewhere the
// rows are there, not pressed.
import { useState } from "react";
import { scopeOf } from "./station.tsx";
import { useDoingList, doingMatches, failed } from "./doing.ts";
import { type Scope, scopesUpTo, useVaultCall, useVaultRequest } from "./vault.ts";
import { Option1, Option2, Option3, Option4 } from "@stillfail/ui/icons.tsx";
import * as css from "./Decisions.css.ts";
import * as own from "./VaultApproval.css.ts";
import { Spinner } from "@stillfail/ui/waiting.tsx";
import { t } from "./i18n.ts";

type Choice = { scope: Scope | null; label: string; detail: string };
/** The rows for an item granted up to `lasts`: its scopes, then 拒绝. */
const choices = (lasts: string | undefined): Choice[] => [
  ...scopesUpTo(lasts).map((s) => ({ scope: s, label: t(`web-pages.vault.approve.${s}`), detail: t(`web-pages.vault.approve.${s}Detail`) })),
  { scope: null, label: t("web-pages.vault.approve.deny"), detail: t("web-pages.vault.approve.denyDetail") },
];
const DIGITS = [Option1, Option2, Option3, Option4];

/**
 * The approval's rows for request `id` (a station's address or a workspace says where). `onDecided` once it went
 * through (the decisions page sends the card on its way).
 */
export function VaultChoices({ workspace, id, onDecided }: { workspace: string; id: string; onDecided?: (() => void) | undefined }) {
  const { view, request } = useVaultRequest(workspace, id);
  const run = useVaultCall();
  const doing = useDoingList().filter((d) => !failed(d) && doingMatches(d, ["vault.approve", "vault.deny"], { workspace, request: id }));
  // What was tapped, while the core has it (and the system asks the person).
  const [pending, setPending] = useState<Choice["scope"] | undefined>(undefined);
  // The plain library's (no security mode) are approved anywhere: nothing is unsealed for them.
  const able = (!!view?.available || view?.plain === true) && request !== undefined;
  const under = pending !== undefined || doing.length > 0;
  const busy = (c: Choice) => pending === c.scope || doing.some((d) => (c.scope === null ? d.call === "vault.deny" : d.call === "vault.approve" && d.params.scope === c.scope));
  const pick = (c: Choice) => {
    if (!able || under) return;
    setPending(c.scope);
    const asked = c.scope === null
      ? run("vault.deny", { workspace, request: id }, t("web-pages.vault.approve.denyWhat"))
      : run("vault.approve", { workspace, request: id, scope: c.scope }, t("web-pages.vault.approve.what"));
    void asked.then((v) => {
      setPending(undefined);
      if (v !== undefined) onDecided?.();
    });
  };
  const rows = choices(request?.lasts);
  // A web page keeps no keys: no rows to look at, only where to go.
  if (view && !view.available && view.plain !== true) {
    return (
      <div className={`${css.options} ${own.inClient}`}>
        <span className={own.inClientTitle}>{t("web-pages.vault.approve.inClient")}</span>
        <span className={own.inClientDetail}>{t("web-pages.vault.approve.inClientDetail")}</span>
      </div>
    );
  }
  return (
    <div className={css.options} role="group" aria-label={request?.itemName ? t("web-pages.vault.approve.wants", { name: request.itemName }) : t("web-main.decisions.options")}>
      {rows.map((c, i) => {
        const Digit = DIGITS[i]!;
        const now = busy(c);
        const recommended = i === rows.length - 2;
        return (
          <button key={c.label} type="button" className={css.choice} data-recommended={recommended || undefined} data-busy={now || undefined}
            disabled={!able || under} aria-busy={now || undefined} aria-description={recommended ? t("common.recommended") : undefined} onClick={() => pick(c)}>
            <span className={css.choiceNumber} aria-hidden="true"><Digit size={20} /></span>
            <span className={css.choiceLabel}>{c.label}</span>
            <span className={css.choiceDetail}>{c.detail}</span>
            {now && <Spinner inline className={css.choiceSpinner} />}
          </button>
        );
      })}
    </div>
  );
}

/** The approval under a card that names a vault request (`card.vault`), at a station's `address`. */
export function VaultCard({ address, id, onDecided }: { address: string; id: string; onDecided?: (() => void) | undefined }) {
  return <VaultChoices workspace={scopeOf(address)} id={id} onDecided={onDecided} />;
}
