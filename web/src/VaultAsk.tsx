// An agent's request to use a vault item, in its chat (docs/vault.md 申请和授权): drawn from its card (`card.vaultAsk`,
// station/src/vault/secrets.ts) in place of the post's words. One card: the item and how it is given, why, the command;
// under a rule the approval's rows while it waits (VaultApproval.tsx), how it ended once decided.
import { useLayoutEffect, useRef, useState, type ReactNode } from "react";
import type { ChatMessage, VaultAsk as Ask } from "./core/shapes.ts";
import { Check, Close, Key, Wait } from "@stillfail/ui/icons.tsx";
import { VaultCard } from "./VaultApproval.tsx";
import { useStation } from "./station.tsx";
import { modeName } from "./vault.ts";
import * as css from "./VaultAsk.css.ts";
import { t } from "./i18n.ts";

/** The command, three lines of it with a way to the rest when it runs longer. */
function Command({ text }: { text: string }) {
  const box = useRef<HTMLElement>(null);
  const [open, setOpen] = useState(false);
  const [long, setLong] = useState(false);
  useLayoutEffect(() => {
    const el = box.current;
    if (el && !open) setLong(el.scrollHeight > el.clientHeight + 1);
  }, [text, open]);
  return <>
    <pre className={css.command}><code ref={box} className={css.commandText} data-open={open || undefined}>{text}</code></pre>
    {(long || open) && <button type="button" className={css.more} onClick={() => setOpen(!open)}>{t(open ? "web-pages.vault.ask.less" : "web-pages.vault.ask.more")}</button>}
  </>;
}

const scopeName = (scope: string | undefined): string =>
  scope === "hour" ? t("web-pages.vault.approve.hour") : scope === "chat" ? t("web-pages.vault.ask.scopeChat") : t("web-pages.vault.approve.once");

/** How it ended: 已批准 · 仅本次, 已拒绝, 已过期. */
function Outcome({ ask }: { ask: Ask }) {
  const [Icon, words] = ask.status === "granted" ? [Check, t("web-pages.vault.ask.granted", { scope: scopeName(ask.scope) })]
    : ask.status === "denied" ? [Close, t("web-pages.vault.ask.denied")]
    : [Wait, t("web-pages.vault.ask.expired")];
  return <div className={css.outcome} data-tone={ask.status}><Icon size={16} />{words}</div>;
}

/**
 * The request `ask` the post `m` makes; `children` under it (its 忽略). `rows`: the approval's in it (the decisions page
 * has them at its foot instead).
 */
export function VaultAsk({ message: m, ask, rows = true, children }: { message: ChatMessage; ask: Ask; rows?: boolean; children?: ReactNode }) {
  const station = useStation().address;
  const waiting = rows && !!m.card?.vault && !m.decision?.resolved && !ask.status;
  return <>
    <div className={css.card}>
      <div className={css.info}>
        <div className={css.head}>
          <span className={css.key} aria-hidden="true"><Key size={14} /></span>
          <span className={css.verb}>{t("web-pages.vault.ask.wants")}</span>
          <span className={css.name}>{ask.name}</span>
          <span className={css.tag}>{modeName(ask.mode)}</span>
          {ask.hosts.map((h) => <span key={h} className={`${css.tag} ${css.host}`}>{h}</span>)}
        </div>
        {ask.reason && <p className={css.reason}>{ask.reason}</p>}
        {ask.command && <Command text={ask.command} />}
      </div>
      {(waiting || ask.status) && <div className={css.rule} />}
      {ask.status ? <Outcome ask={ask} /> : waiting && <>
        {m.card?.assigneeText && <p className={css.who}>{m.card.assigneeText}</p>}
        <div className={css.rows}><VaultCard address={station} id={m.card!.vault!} /></div>
      </>}
    </div>
    {children}
  </>;
}
