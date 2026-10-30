// An agent's request about a vault item, in its chat (docs/vault.md): to use one (申请和授权) or to keep one (agent 存入),
// drawn from its card (`card.vaultAsk`, station/src/vault/secrets.ts) in place of the post's words. A card of words
// (docs/ui-panels.md 页面卡片): what is asked, in its title; what will run; a risk, only where there is one; the answer's
// buttons at its foot (VaultApproval.tsx). Once decided, one line saying how it ended; decided on screen, the card
// first stays as it was, the answer given as it was and the rest greyed, none pressed, till it is out of sight
// (settling.tsx, docs/list-motion.md).
import type { ChatMessage, VaultAsk as Ask, VaultSave } from "./core/shapes.ts";
import { VaultCard } from "./VaultApproval.tsx";
import { useSettling } from "./settling.tsx";
import { useStation } from "./station.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as css from "./VaultAsk.css.ts";
import { t } from "./i18n.ts";
import { useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { ENTER, play } from "@stillfail/ui/motion.ts";

/** What a request's card says: the item, how it would be given, the command it is for (or, one to keep, what it is). */
export type Asked = { name: string; mode: string; command?: string | null | undefined; save?: VaultSave | undefined; station?: string | undefined };

/**
 * The words of `key` with the item's name in them set apart by how it looks (`css.name` in a quiet line, `css.titleName`
 * in a title), not by quotes (docs/ui-panels.md 文字).
 */
function named(key: string, args: Record<string, string>, name: string, className: string): ReactNode {
  const parts = t(key, { ...args, name: NAME }).split(NAME);
  return parts.flatMap((p, i) => i === 0 ? [p] : [<span key={i} className={className}>{name}</span>, p]);
}

/** Where the name goes while the words are filled in (named), to split them there. */
const NAME = "\u0000";

/** Its title: 使用 GitHub token, 存入密码 UniFi UX7 管理员 (the name heavier than the words). */
export const askTitle = (a: Asked): ReactNode =>
  a.save ? named("web-pages.vault.ask.save", { kind: t(`web-pages.vault.ask.kind.${a.save.kind}`) }, a.name, css.titleName)
    : named("web-pages.vault.ask.use", {}, a.name, css.titleName);

/**
 * A request as a card: its title (and, one to keep, the account), the command, a risk; `children` at its foot. `fill`:
 * as wide as the page's other cards (the vault's page), not as what it says (a chat's).
 */
export function AskCard({ ask, fill = false, children }: { ask: Asked; fill?: boolean; children?: ReactNode }) {
  // Only what is out of the ordinary is said: a command that can read the secret itself, or runs on another station.
  const risky = !ask.save && (ask.mode === "env" || ask.mode === "file");
  const elsewhere = !ask.save && ask.station ? t("web-pages.vault.ask.on", { station: ask.station }) : null;
  return (
    <div className={`${pagesCss.card} ${fill ? "" : css.card}`}>
      <div className={css.what}>
        <div className={css.title}>{askTitle(ask)}{(ask.save?.username || ask.save?.filename) && <span className={css.sub}>{ask.save.username || ask.save.filename}</span>}</div>
        {!ask.save && ask.command && <div className={css.command} title={ask.command}>{ask.command}</div>}
        {(risky || elsewhere) && <div className={css.note}>{risky && <span className={css.risk}>{t("web-pages.vault.ask.plain")}</span>}{risky && elsewhere && " · "}{elsewhere}</div>}
      </div>
      {children}
    </div>
  );
}

const scopeName = (scope: string | undefined): string => t(`web-pages.vault.scope.${scope === "once" || scope === "hour" ? scope : "chat"}`);

/** How it ended, in a line: 已存入密码 …, 已允许使用 … · 本对话内, 已拒绝使用 …, 已过期 (the name in the strong ink). */
function Outcome({ ask }: { ask: Ask }) {
  const kind = ask.save ? t(`web-pages.vault.ask.kind.${ask.save.kind}`) : "";
  const words = ask.status === "granted"
    ? ask.save ? named("web-pages.vault.ask.kept", { kind }, ask.name, css.name) : named("web-pages.vault.ask.granted", { scope: scopeName(ask.scope) }, ask.name, css.name)
    : ask.status === "denied" ? named(ask.save ? "web-pages.vault.ask.notKept" : "web-pages.vault.ask.denied", {}, ask.name, css.name)
    : t("web-pages.vault.ask.expired");
  return <div className={css.outcome}><span className={css.dot} data-tone={ask.status} aria-hidden="true" /><span>{words}</span></div>;
}

/** The request `ask` the post `m` makes. `rows`: the answer's buttons in it (none where the message is drawn out of its chat). */
export function VaultAsk({ message: m, ask, rows = true }: { message: ChatMessage; ask: Ask; rows?: boolean }) {
  const station = useStation().address;
  const box = useRef<HTMLDivElement>(null);
  const open = !ask.status;
  const [drawnOpen, setDrawnOpen] = useState(open);
  useSettling(box, open, drawnOpen, setDrawnOpen);
  if (!open && !drawnOpen) return <Outcome ask={ask} />;
  const buttons = rows && !!m.card?.vault;
  // (decided where its buttons were shown: how it went in their place, as high as they were)
  const foot = !buttons ? null : open ? !m.decision?.resolved && <VaultCard address={station} id={m.card!.vault!} who={m.card?.assigneeText} />
    : <div className={pagesCss.cardFoot}><Arrived><Outcome ask={ask} /></Arrived></div>;
  return <div ref={box}><AskCard ask={ask}>{foot}</AskCard></div>;
}

/** What comes in a card's place once it is answered while it shows: fading in where it is (motion.ts ENTER). */
function Arrived({ children }: { children: ReactNode }) {
  const el = useRef<HTMLDivElement>(null);
  useLayoutEffect(() => { play(el.current, [{ opacity: 0 }, { opacity: 1 }], ENTER); }, []);
  return <div ref={el}>{children}</div>;
}
