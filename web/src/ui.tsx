// The app's own parts beside @stillfail/ui's (its parts.tsx, all of which this gives too): what made an agent's model,
// a connect's kind, a time, a page's way back, the splash, page changes. The tips' keys are the app's keymap's.
import { Mark } from "./brand.tsx";
import { shortcutOf, useKeymap } from "./keymap.ts";
import { setPrefs, usePrefs } from "./prefs.ts";
import type { Badge, Maker, RuntimeKind, Stamp } from "./api.ts";
import { RUNTIME_LABEL } from "./format.ts";
import { FeishuLogo, RuntimeLogo as RuntimeMark, SlackLogo } from "@stillfail/ui/brands.tsx";
export { FeishuLogo, SlackLogo };
import { Chat, Check, ChevronLeft, Wait, Plug, Refresh, Sliders } from "@stillfail/ui/icons.tsx";
import { setShortcuts } from "@stillfail/ui/shortcuts.ts";
import { motionMs } from "@stillfail/ui/motion.ts";
import { ICON, Tip } from "@stillfail/ui/parts.tsx";
import { flushSync } from "react-dom";
import { Link, useNavigate } from "react-router";
import { useEffect, useState, type CSSProperties, type ReactNode } from "react";
import * as pagesCss from "./styles/pages.css.ts";
import * as css from "./ui.css.ts";
import * as chatCss from "./styles/chat.css.ts";
import * as waitingCss from "./styles/waiting.css.ts";
import { t } from "./i18n.ts";
import { MONO } from "./modelMarks.ts";
import { reload } from "./reloads.ts";

export * from "@stillfail/ui/parts.tsx";
export * from "@stillfail/ui/waiting.tsx";

setShortcuts({ keys: shortcutOf, use: useKeymap });

/**
 * Keep a completed or waiting state compact while retaining its explanation and accessible name: a check, an open arc and dots
 * in its words' place. Which leads it is the core's (`lead`, with what follows it: `rest`; client/core-ts present.ts
 * Lead), not read out of its words.
 */
export function StatusText({ text, lead, rest }: { text: string; lead?: string | null | undefined; rest?: string | null | undefined }) {
  const done = lead === "done";
  if (!done && lead !== "wait") return <>{text}</>;
  const label = t(done ? "web-main.status.done" : "web-main.status.waiting");
  const reason = rest ?? "";
  return <><Tip label={label}><span className={css.doneMark} role="img" aria-label={label}>{done ? <Check size={14} strokeWidth={1.7} /> : <Wait size={14} strokeWidth={1.7} />}</span></Tip>{reason && <> {reason}</>}</>;
}

/** A back link that only phones show, where an opened page hides the sidebar. */
export function MobileBack({ to, label }: { to: string; label: string }) {
  return <Link className={css.mobileBack} to={to}><ChevronLeft {...ICON} />{label}</Link>;
}

/**
 * A detail page's way back, on every screen: to the page it was opened from (a step back in history), or when it was
 * opened directly, to `to`.
 */
export function BackLink({ to, label }: { to: string; label: string }) {
  const navigate = useNavigate();
  return (
    // In a row of its own, which takes the page's column (the link alone would not line up with it).
    <div className={css.pageBackRow}>
      <Link className={css.pageBack} to={to} onClick={(e) => {
        if (((window.history.state as { idx?: number } | null)?.idx ?? 0) > 0) { e.preventDefault(); navigate(-1); }
      }}><ChevronLeft {...ICON} />{label}</Link>
    </div>
  );
}

const KIND_ICON = { slack: SlackLogo, feishu: FeishuLogo, wechat: Chat } as const;

/** What a connect connects to, as an icon: its kind, not its identity. */
export function ConnectKindIcon({ kind, size = 16, tile }: { kind: string; size?: number; tile?: boolean }) {
  const Icon = KIND_ICON[kind as keyof typeof KIND_ICON] ?? Chat;
  const icon = <Icon size={size} strokeWidth={1.7} aria-hidden="true" />;
  return tile ? <span className={`${pagesCss.mark} ${css.kindMark}`} style={{ width: size * 2.4, height: size * 2.4 }}>{icon}</span> : <span className={css.kindIcon}>{icon}</span>;
}

/** A connect as its people see it in Slack: its bot's picture; its kind's icon until Slack has said what that is. */
export function ConnectAvatar({ connect, size = 28 }: { connect: { kind: string; botImage?: string | null | undefined }; size?: number }) {
  if (!connect.botImage) return <ConnectKindIcon kind={connect.kind} size={Math.round(size * 0.6)} tile={size > 32} />;
  return <img className={chatCss.botAvatar} src={connect.botImage} width={size} height={size} alt="" loading="lazy" referrerPolicy="no-referrer" />;
}

/** Where a thread elsewhere is (a place's `surface`, a connect's kind): Feishu's mark for Feishu, else Slack's. */
export function ElsewhereLogo({ kind, size = 16 }: { kind: string | null | undefined; size?: number }) {
  return kind === "feishu" || kind?.startsWith("feishu:") ? <FeishuLogo size={size} /> : <SlackLogo size={size} />;
}

/**
 * How long a splash may stand before it offers to load the page again: past it, something is stuck (a core that never
 * answers, a load that never ends), and an app on the home screen has no reload of its own.
 */
const SPLASH_STUCK_MS = 10_000;

/**
 * The app starting (or waiting for what every page needs): the mark. What it waits for is said only when
 * it takes a while (after a second), or at once when `now` (a failure); standing too long, it offers a reload.
 */
export function Splash({ label, now = false, children }: { label?: string; now?: boolean; children?: ReactNode }) {
  const [stuck, setStuck] = useState(false);
  useEffect(() => {
    const timer = setTimeout(() => setStuck(true), SPLASH_STUCK_MS);
    return () => clearTimeout(timer);
  }, []);
  return (
    <div className="splash" role="status" aria-live="polite">
      <Mark size={56} className="splash-mark" />
      {label && <p className={css.splashLabel} data-now={now || undefined}>{label}</p>}
      {children}
      {stuck && <button type="button" className={css.splashReload} onClick={() => reload("button")}><Refresh size={14} />{t("common.reload")}</button>}
    </div>
  );
}

/** A runtime's mark (brands.tsx), as the app's rows and headings place it (cloud/settings.css.ts finds it by its class). */
export function RuntimeLogo({ runtime, size = 16 }: { runtime: RuntimeKind; size?: number }) {
  return <RuntimeMark runtime={runtime} size={size} className={css.runtimeLogo} />;
}

/**
 * The mark of the company that made a model (the core says which); the runtime's mark when it does not know. No tip of
 * its own: it sits in tabs, rows and buttons that have theirs, and one thing shows one tip.
 */
export function ModelLogo({ maker, runtime, size = 14 }: { maker: Maker | null | undefined; runtime: RuntimeKind; size?: number }) {
  if (!maker) return <RuntimeLogo runtime={runtime} size={size} />;
  return <img className={css.modelLogo} src={`${import.meta.env.BASE_URL}models/${maker.id}.svg`} alt={maker.name} width={size} height={size} data-mono={MONO.has(maker.id) || undefined} />;
}

/** OpenCode's mark: a hollow square, drawn to match the 1.7 stroke icons. */
function OpenCodeMark({ size = 16 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.4} aria-hidden="true">
      <rect x="6" y="4" width="12" height="16" />
    </svg>
  );
}

/** Whose service a profile runs on: Anthropic, OpenAI or xAI for a subscription or an API key, OpenCode for OpenCode Go. */
export function ProviderLogo({ runtime, kind, mark, size = 16 }: { runtime: RuntimeKind; kind: string; mark?: string | null | undefined; size?: number }) {
  if (kind === "opencode-go" || mark === "opencode") return <OpenCodeMark size={size} />;
  if (kind === "env") return <Sliders size={size} strokeWidth={1.7} aria-hidden="true" />;
  // A key on a listed provider: its maker's mark, or the generic plug where there is none.
  if (kind === "api-provider") return mark ? <ModelLogo maker={{ id: mark, name: mark }} runtime={runtime} size={size} /> : <Plug size={size} strokeWidth={1.7} aria-hidden="true" />;
  const maker = runtime === "claude" || kind === "anthropic-api" ? { id: "anthropic", name: "Anthropic" } : runtime === "grok" ? { id: "xai", name: "xAI" } : runtime === "cursor" ? { id: "cursor", name: "Cursor" } : runtime === "devin" ? { id: "devin", name: "Devin" } : { id: "openai", name: "OpenAI" };
  return <ModelLogo maker={maker} runtime={runtime} size={size} />;
}

/** A runtime's name, short, for the tags after a profile's name. */
const RUNTIME_TAG: Record<RuntimeKind, string> = { claude: "CC", codex: "Codex", dsh: "DSH", grok: "GROK", cursor: "Cursor", devin: "Devin", hermes: "Hermes" };

/** The runtimes a profile runs, as small marks after its name (CC for Claude Code, Codex, DSH for DeepSeek Harness, GROK for Grok Build, Cursor, Devin), and 自动决策 where it serves the automatic decisions. */
export function RuntimeTags({ runtimes, decision = false }: { runtimes: RuntimeKind[]; decision?: boolean | undefined }) {
  return (
    <span className={waitingCss.runtimeTags}>
      {runtimes.map((r) => <Tip key={r} label={RUNTIME_LABEL[r]}><span className={waitingCss.runtimeTag}><RuntimeLogo runtime={r} size={12} />{RUNTIME_TAG[r]}</span></Tip>)}
      {decision && <Tip label={t("common.decisionLong")}><span className={waitingCss.runtimeTag}>{t("common.decision")}</span></Tip>}
    </span>
  );
}

/**
 * An agent as the phone shows it: its model's maker on a tile, and where it stands as a badge. `children`: the station it
 * runs on, on the same tile after the maker (its icon, or its name where it has none); `wrap` then puts the maker in its
 * own control, the station's part being one of its own.
 */
export function AgentMark({ maker, runtime, badge, badgeText, size = 20, wrap, children }: {
  maker: Maker | null | undefined; runtime: RuntimeKind; badge: Badge | undefined; badgeText?: string | undefined; size?: number;
  wrap?: ((logo: ReactNode) => ReactNode) | undefined; children?: ReactNode;
}) {
  const logo = <ModelLogo maker={maker} runtime={runtime} size={Math.round(size * 0.62)} />;
  // (its badge as a 20 one's, as much smaller on a smaller mark: ui.css.ts agentMark)
  const sized = { "--mark": `${size}px`, "--badge": String(Math.min(size / 20, 1)) } as CSSProperties;
  if (children == null) {
    return <span className={css.agentMark} style={sized} data-badge={badge ?? undefined} role="img" aria-label={badgeText ?? undefined}>{logo}</span>;
  }
  return (
    <span className={`${css.agentMark} ${css.agentMarkJoined}`} style={sized} data-badge={badge ?? undefined}>
      {wrap ? wrap(logo) : logo}{children}
    </span>
  );
}

/** Every relative time on the page follows one switch, kept on this device (prefs.ts): a click on any of them flips all between "3 分钟前" and the date. */
function useAbsoluteTime(): [boolean, () => void] {
  const absolute = usePrefs((p) => p.absoluteTime);
  return [absolute, () => setPrefs({ absoluteTime: !absolute })];
}

/** A time as the core says it (fresh each minute): relative by default; clicking flips every time on the page to absolute and back. `fixed`: always relative, not a switch (the sidebar's), the date on hover. */
export function Time({ stamp, className, fixed = false }: { stamp: Stamp | undefined; className?: string; fixed?: boolean }) {
  const [switched, flip] = useAbsoluteTime();
  if (!stamp) return null;
  const absolute = switched && !fixed;
  return (
    <Tip label={absolute ? stamp.ago : stamp.full}><time className={`${fixed ? "" : css.timeToggle}${className ? ` ${className}` : ""}`.trim()} dateTime={new Date(stamp.at).toISOString()}
      data-full={stamp.full} onClick={fixed ? undefined : (e) => { e.preventDefault(); e.stopPropagation(); flip(); }}>
      {absolute ? stamp.full : stamp.ago}
    </time></Tip>
  );
}

let changing: { settle: (() => void)[]; moving: Promise<void>; done: Promise<void> } | null = null;
/**
 * While a page change (transitionTo) is under way: `settle` is run once the next page is there, as its picture is about
 * to be taken; `moving` is when the change starts to move, `done` when it is over. Else null.
 */
export function pageChanging(): { settle: (() => void)[]; moving: Promise<void>; done: Promise<void> } | null {
  return changing;
}

/**
 * One page becoming another in a view transition (what both have and name moves between them; the rest crossfades):
 * `go` navigates, rendered at once; with `ready`, the new page is waited for (a little) until it shows what the
 * transition lands on. `patience`: how long (ms) the new page is waited for at most. Plainly without the API; with
 * motion reduced, the same, over at once (styles/global.css.ts).
 * Resolves when it is over.
 */
export function transitionTo(go: () => void, ready?: () => boolean, patience = 800): Promise<void> {
  if (!document.startViewTransition) { go(); return Promise.resolve(); }
  // What is named for it only while it runs (its styles): a named element blurs nothing behind it (the composer's glass).
  document.documentElement.dataset.transitioning = "";
  const transition = document.startViewTransition(async () => {
    flushSync(go);
    const until = performance.now() + patience;
    while (ready && !ready() && performance.now() < until) await new Promise((r) => setTimeout(r, 16));
    for (const settle of now.settle.splice(0)) settle();
  });
  const now = { settle: [] as (() => void)[], moving: transition.ready.catch(() => {}), done: transition.finished.catch(() => {}) };
  changing = now;
  return transition.finished.catch(() => {}).finally(() => { if (changing === now) changing = null; delete document.documentElement.dataset.transitioning; });
}

/** A page change whose leaving elements are kept by its caller: no document snapshot or rendering freeze. */
export function transitionLive(go: () => void, ready: () => boolean, duration: number): Promise<void> {
  let begin!: () => void;
  const moving = new Promise<void>((resolve) => { begin = resolve; });
  const now = { settle: [] as (() => void)[], moving, done: Promise.resolve() };
  changing = now;
  now.done = Promise.resolve().then(async () => {
    flushSync(go);
    // Composer layout effects queue their own setup; let them join settle before measuring the destination.
    await Promise.resolve();
    const until = performance.now() + 800;
    while (!ready() && performance.now() < until) await new Promise((resolve) => setTimeout(resolve, 16));
    for (const settle of now.settle.splice(0)) settle();
    begin();
    await new Promise((resolve) => setTimeout(resolve, motionMs(duration)));
  }).finally(() => {
    begin();
    if (changing === now) changing = null;
  });
  return now.done;
}
