// An agent's request to use a vault item (docs/vault.md 申请和授权): under the agent's post in its chat, on the
// decisions page (奏) and on the vault's page, in place of the card's options. Three rows as a decision's options are
// drawn (Decisions.css.ts): 仅本次 (`once`), 本对话 1 小时内 (`hour`), 拒绝; the first recommended. A tap asks the core
// (`vault.approve`, which has the system ask the person; `vault.deny`); once decided the station takes the card back.
// Only the request's own (the `vaults` topic's requests: one waiting on the viewer) can be answered, and only in an app
// that keeps keys: a web page shows no rows, only that it is approved in a client (desktop or Android); elsewhere the
// rows are there, not pressed.
import { useState } from "react";
import { scopeOf } from "./station.tsx";
import { useDoingList, doingMatches, failed } from "./doing.ts";
import { useVaultCall, useVaultRequest } from "./vault.ts";
import { Option1, Option2, Option3 } from "@stillfail/ui/icons.tsx";
import * as css from "./Decisions.css.ts";
import * as own from "./VaultApproval.css.ts";
import * as spinnerCss from "@stillfail/ui/styles/spinner.css.ts";
import { t } from "./i18n.ts";

type Choice = { scope: "once" | "hour" | null; label: string; detail: string };
const choices = (): Choice[] => [
  { scope: "once", label: t("web-pages.vault.approve.once"), detail: t("web-pages.vault.approve.onceDetail") },
  { scope: "hour", label: t("web-pages.vault.approve.hour"), detail: t("web-pages.vault.approve.hourDetail") },
  { scope: null, label: t("web-pages.vault.approve.deny"), detail: t("web-pages.vault.approve.denyDetail") },
];
const DIGITS = [Option1, Option2, Option3];

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
      {choices().map((c, i) => {
        const Digit = DIGITS[i]!;
        const now = busy(c);
        return (
          <button key={c.label} type="button" className={css.choice} data-recommended={i === 0 || undefined} data-busy={now || undefined}
            disabled={!able || under} aria-busy={now || undefined} aria-description={i === 0 ? t("common.recommended") : undefined} onClick={() => pick(c)}>
            <span className={css.choiceNumber} aria-hidden="true"><Digit size={20} /></span>
            <span className={css.choiceLabel}>{c.label}</span>
            <span className={css.choiceDetail}>{c.detail}</span>
            {now && <span className={`${spinnerCss.spinner} ${css.choiceSpinner}`} aria-hidden="true" />}
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
