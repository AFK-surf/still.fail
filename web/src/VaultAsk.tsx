// An agent's request about a vault item, in its chat (docs/vault.md): to use one (申请和授权) or to keep one (agent 存入),
// drawn from its card (`card.vaultAsk`, station/src/vault/secrets.ts) in place of the post's words. A card of words
// (docs/ui-panels.md 页面卡片): what is asked, in its title; what will run; a risk, only where there is one; the answer's
// buttons at its foot (VaultApproval.tsx). Once decided, one line saying how it ended.
import type { ChatMessage, VaultAsk as Ask, VaultSave } from "./core/shapes.ts";
import { VaultCard } from "./VaultApproval.tsx";
import { useStation } from "./station.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as css from "./VaultAsk.css.ts";
import { t } from "./i18n.ts";
import type { ReactNode } from "react";

/** What a request's card says: the item, how it would be given, the command it is for (or, one to keep, what it is). */
export type Asked = { name: string; mode: string; command?: string | null | undefined; save?: VaultSave | undefined; station?: string | undefined };

/** Its title: 使用「GitHub token」, 存入密码「UniFi UX7 管理员」. */
export const askTitle = (a: Asked): string =>
  a.save ? t("web-pages.vault.ask.save", { kind: t(`web-pages.vault.ask.kind.${a.save.kind}`), name: a.name }) : t("web-pages.vault.ask.use", { name: a.name });

/**
 * A request as a card: its title (and, one to keep, the account), the command, a risk; `children` at its foot. `fill`:
 * as wide as the page's other cards (the vault's page), not as what it says (a chat's).
 */
export function AskCard({ ask, fill = false, children }: { ask: Asked; fill?: boolean; children?: ReactNode }) {
  // Only what is out of the ordinary is said: a command that can read the secret itself, or runs on another station.
  const risky = !ask.save && ask.mode === "env";
  const elsewhere = !ask.save && ask.station ? t("web-pages.vault.ask.on", { station: ask.station }) : null;
  return (
    <div className={`${pagesCss.card} ${fill ? "" : css.card}`}>
      <div className={css.what}>
        <div className={css.title}>{askTitle(ask)}{ask.save?.username && <span className={css.sub}>{ask.save.username}</span>}</div>
        {!ask.save && ask.command && <div className={css.command} title={ask.command}>{ask.command}</div>}
        {(risky || elsewhere) && <div className={css.note}>{risky && <span className={css.risk}>{t("web-pages.vault.ask.plain")}</span>}{risky && elsewhere && " · "}{elsewhere}</div>}
      </div>
      {children}
    </div>
  );
}

const scopeName = (scope: string | undefined): string => t(`web-pages.vault.scope.${scope === "once" || scope === "hour" ? scope : "chat"}`);

/** How it ended, in a line: 已存入密码「…」, 已允许使用「…」· 本对话内, 已拒绝使用「…」, 已过期. */
function Outcome({ ask }: { ask: Ask }) {
  const kind = ask.save ? t(`web-pages.vault.ask.kind.${ask.save.kind}`) : "";
  const words = ask.status === "granted"
    ? ask.save ? t("web-pages.vault.ask.kept", { kind, name: ask.name }) : t("web-pages.vault.ask.granted", { name: ask.name, scope: scopeName(ask.scope) })
    : ask.status === "denied" ? t(ask.save ? "web-pages.vault.ask.notKept" : "web-pages.vault.ask.denied", { name: ask.name })
    : t("web-pages.vault.ask.expired");
  return <div className={css.outcome}><span className={css.dot} data-tone={ask.status} aria-hidden="true" />{words}</div>;
}

/** The request `ask` the post `m` makes. `rows`: the answer's buttons in it (the decisions page has them at its foot). */
export function VaultAsk({ message: m, ask, rows = true }: { message: ChatMessage; ask: Ask; rows?: boolean }) {
  const station = useStation().address;
  if (ask.status) return <Outcome ask={ask} />;
  const waiting = rows && !!m.card?.vault && !m.decision?.resolved;
  return <AskCard ask={ask}>{waiting && <VaultCard address={station} id={m.card!.vault!} who={m.card?.assigneeText} />}</AskCard>;
}
