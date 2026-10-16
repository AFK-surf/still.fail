// The app's own parts beside @stillfail/ui's (its parts.tsx, all of which this gives too): what made an agent's model,
// a connect's kind, a time, a page's way back, the splash, page changes. The tips' keys are the app's keymap's.
import { Mark } from "./brand.tsx";
import { shortcutOf, useKeymap } from "./keymap.ts";
import { setPrefs, usePrefs } from "./prefs.ts";
import type { Badge, Maker, Stamp } from "./api.ts";
import { Chat, Check, ChevronLeft, Wait, Plug, Refresh, Sliders } from "@stillfail/ui/icons.tsx";
import { setShortcuts } from "@stillfail/ui/shortcuts.ts";
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

export * from "@stillfail/ui/parts.tsx";

setShortcuts({ keys: shortcutOf, use: useKeymap });

/**
 * Keep a completed or waiting state compact while retaining its explanation and accessible name: a check, an open arc and dots
 * in its words' place. The core says it in words, in either language (client/core-ts present.ts: 做完了, 做完了：<why>;
 * Done, Done: <why>; 等待中, 在等：<what>; Waiting, Waiting: <what>).
 */
export function StatusText({ text }: { text: string }) {
  const done = /^(?:(?:做完了|已完成)(?:：|$)|Done(?:: |$))/.exec(text);
  const wait = done ? null : /^(?:在等：|等待：|等待中$|Waiting(?:: |$))/.exec(text);
  const lead = done ?? wait;
  if (!lead) return <>{text}</>;
  const label = t(done ? "web-main.status.done" : "web-main.status.waiting");
  const reason = text.slice(lead[0].length);
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

const KIND_ICON = { slack: SlackLogo, wechat: Chat } as const;

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

/** Slack's mark in its own colours, sized like the line icons around it. */
export function SlackLogo({ size = 16 }: { size?: number; strokeWidth?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 54 54" aria-hidden="true" className="slack-logo">
      <path fill="#36C5F0" d="M19.712.133a5.381 5.381 0 0 0-5.376 5.387 5.381 5.381 0 0 0 5.376 5.386h5.376V5.52A5.381 5.381 0 0 0 19.712.133m0 14.365H5.376A5.381 5.381 0 0 0 0 19.884a5.381 5.381 0 0 0 5.376 5.387h14.336a5.381 5.381 0 0 0 5.376-5.387 5.381 5.381 0 0 0-5.376-5.386" />
      <path fill="#2EB67D" d="M53.76 19.884a5.381 5.381 0 0 0-5.376-5.386 5.381 5.381 0 0 0-5.376 5.386v5.387h5.376a5.381 5.381 0 0 0 5.376-5.387m-14.336 0V5.52A5.381 5.381 0 0 0 34.048.133a5.381 5.381 0 0 0-5.376 5.387v14.364a5.381 5.381 0 0 0 5.376 5.387 5.381 5.381 0 0 0 5.376-5.387" />
      <path fill="#ECB22E" d="M34.048 54a5.381 5.381 0 0 0 5.376-5.387 5.381 5.381 0 0 0-5.376-5.386h-5.376v5.386A5.381 5.381 0 0 0 34.048 54m0-14.365h14.336a5.381 5.381 0 0 0 5.376-5.386 5.381 5.381 0 0 0-5.376-5.387H34.048a5.381 5.381 0 0 0-5.376 5.387 5.381 5.381 0 0 0 5.376 5.386" />
      <path fill="#E01E5A" d="M0 34.249a5.381 5.381 0 0 0 5.376 5.386 5.381 5.381 0 0 0 5.376-5.386v-5.387H5.376A5.381 5.381 0 0 0 0 34.249m14.336 0v14.364A5.381 5.381 0 0 0 19.712 54a5.381 5.381 0 0 0 5.376-5.387V34.249a5.381 5.381 0 0 0-5.376-5.387 5.381 5.381 0 0 0-5.376 5.387" />
    </svg>
  );
}

/**
 * How long a splash may stand before it offers to load the page again: past it, something is stuck (a core that never
 * answers, a load that never ends), and an app on the home screen has no reload of its own.
 */
const SPLASH_STUCK_MS = 10_000;

/**
 * The app starting (or waiting for what every page needs): the buddy, floating. What it waits for is said only when
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
      {stuck && <button type="button" className={css.splashReload} onClick={() => location.reload()}><Refresh size={14} />{t("common.reload")}</button>}
    </div>
  );
}

/** The agent runtimes' marks: Claude's in its orange, OpenAI's (Codex) in the text colour. Paths from simple-icons (CC0). */
export function RuntimeLogo({ runtime, size = 16 }: { runtime: "claude" | "codex"; size?: number }) {
  return runtime === "claude" ? (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-label="Claude Code" role="img" className={css.runtimeLogo}><path fill="#D97757" d="m4.7144 15.9555 4.7174-2.6471.079-.2307-.079-.1275h-.2307l-.7893-.0486-2.6956-.0729-2.3375-.0971-2.2646-.1214-.5707-.1215-.5343-.7042.0546-.3522.4797-.3218.686.0608 1.5179.1032 2.2767.1578 1.6514.0972 2.4468.255h.3886l.0546-.1579-.1336-.0971-.1032-.0972L6.973 9.8356l-2.55-1.6879-1.3356-.9714-.7225-.4918-.3643-.4614-.1578-1.0078.6557-.7225.8803.0607.2246.0607.8925.686 1.9064 1.4754 2.4893 1.8336.3643.3035.1457-.1032.0182-.0728-.164-.2733-1.3539-2.4467-1.445-2.4893-.6435-1.032-.17-.6194c-.0607-.255-.1032-.4674-.1032-.7285L6.287.1335 6.6997 0l.9957.1336.419.3642.6192 1.4147 1.0018 2.2282 1.5543 3.0296.4553.8985.2429.8318.091.255h.1579v-.1457l.1275-1.706.2368-2.0947.2307-2.6957.0789-.7589.3764-.9107.7468-.4918.5828.2793.4797.686-.0668.4433-.2853 1.8517-.5586 2.9021-.3643 1.9429h.2125l.2429-.2429.9835-1.3053 1.6514-2.0643.7286-.8196.85-.9046.5464-.4311h1.0321l.759 1.1293-.34 1.1657-1.0625 1.3478-.8804 1.1414-1.2628 1.7-.7893 1.36.0729.1093.1882-.0183 2.8535-.607 1.5421-.2794 1.8396-.3157.8318.3886.091.3946-.3278.8075-1.967.4857-2.3072.4614-3.4364.8136-.0425.0304.0486.0607 1.5482.1457.6618.0364h1.621l3.0175.2247.7892.522.4736.6376-.079.4857-1.2142.6193-1.6393-.3886-3.825-.9107-1.3113-.3279h-.1822v.1093l1.0929 1.0686 2.0035 1.8092 2.5075 2.3314.1275.5768-.3218.4554-.34-.0486-2.2039-1.6575-.85-.7468-1.9246-1.621h-.1275v.17l.4432.6496 2.3436 3.5214.1214 1.0807-.17.3521-.6071.2125-.6679-.1214-1.3721-1.9246L14.38 17.959l-1.1414-1.9428-.1397.079-.674 7.2552-.3156.3703-.7286.2793-.6071-.4614-.3218-.7468.3218-1.4753.3886-1.9246.3157-1.53.2853-1.9004.17-.6314-.0121-.0425-.1397.0182-1.4328 1.9672-2.1796 2.9446-1.7243 1.8456-.4128.164-.7164-.3704.0667-.6618.4008-.5889 2.386-3.0357 1.4389-1.882.929-1.0868-.0062-.1579h-.0546l-6.3385 4.1164-1.1293.1457-.4857-.4554.0608-.7467.2307-.2429 1.9064-1.3114Z" /></svg>
  ) : (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-label="Codex" role="img" className={css.runtimeLogo}><path fill="currentColor" d="M22.2819 9.8211a5.9847 5.9847 0 0 0-.5157-4.9108 6.0462 6.0462 0 0 0-6.5098-2.9A6.0651 6.0651 0 0 0 4.9807 4.1818a5.9847 5.9847 0 0 0-3.9977 2.9 6.0462 6.0462 0 0 0 .7427 7.0966 5.98 5.98 0 0 0 .511 4.9107 6.051 6.051 0 0 0 6.5146 2.9001A5.9847 5.9847 0 0 0 13.2599 24a6.0557 6.0557 0 0 0 5.7718-4.2058 5.9894 5.9894 0 0 0 3.9977-2.9001 6.0557 6.0557 0 0 0-.7475-7.0729zm-9.022 12.6081a4.4755 4.4755 0 0 1-2.8764-1.0408l.1419-.0804 4.7783-2.7582a.7948.7948 0 0 0 .3927-.6813v-6.7369l2.02 1.1686a.071.071 0 0 1 .038.052v5.5826a4.504 4.504 0 0 1-4.4945 4.4944zm-9.6607-4.1254a4.4708 4.4708 0 0 1-.5346-3.0137l.142.0852 4.783 2.7582a.7712.7712 0 0 0 .7806 0l5.8428-3.3685v2.3324a.0804.0804 0 0 1-.0332.0615L9.74 19.9502a4.4992 4.4992 0 0 1-6.1408-1.6464zM2.3408 7.8956a4.485 4.485 0 0 1 2.3655-1.9728V11.6a.7664.7664 0 0 0 .3879.6765l5.8144 3.3543-2.0201 1.1685a.0757.0757 0 0 1-.071 0l-4.8303-2.7865A4.504 4.504 0 0 1 2.3408 7.872zm16.5963 3.8558L13.1038 8.364 15.1192 7.2a.0757.0757 0 0 1 .071 0l4.8303 2.7913a4.4944 4.4944 0 0 1-.6765 8.1042v-5.6772a.79.79 0 0 0-.407-.667zm2.0107-3.0231l-.142-.0852-4.7735-2.7818a.7759.7759 0 0 0-.7854 0L9.409 9.2297V6.8974a.0662.0662 0 0 1 .0284-.0615l4.8303-2.7866a4.4992 4.4992 0 0 1 6.6802 4.66zM8.3065 12.863l-2.02-1.1638a.0804.0804 0 0 1-.038-.0567V6.0742a4.4992 4.4992 0 0 1 7.3757-3.4537l-.142.0805L8.704 5.459a.7948.7948 0 0 0-.3927.6813zm1.0976-2.3654l2.602-1.4998 2.6069 1.4998v2.9994l-2.5974 1.4997-2.6067-1.4997Z" /></svg>
  );
}

/**
 * The mark of the company that made a model (the core says which); the runtime's mark when it does not know. No tip of
 * its own: it sits in tabs, rows and buttons that have theirs, and one thing shows one tip.
 */
export function ModelLogo({ maker, runtime, size = 14 }: { maker: Maker | null | undefined; runtime: "claude" | "codex"; size?: number }) {
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

/** Whose service a profile runs on: Anthropic or OpenAI for a subscription or an API key, OpenCode for OpenCode Go. */
export function ProviderLogo({ runtime, kind, mark, size = 16 }: { runtime: "claude" | "codex"; kind: string; mark?: string | null | undefined; size?: number }) {
  if (kind === "opencode-go" || mark === "opencode") return <OpenCodeMark size={size} />;
  if (kind === "env") return <Sliders size={size} strokeWidth={1.7} aria-hidden="true" />;
  // A key on a listed provider: its maker's mark, or the generic plug where there is none.
  if (kind === "api-provider") return mark ? <ModelLogo maker={{ id: mark, name: mark }} runtime={runtime} size={size} /> : <Plug size={size} strokeWidth={1.7} aria-hidden="true" />;
  return <ModelLogo maker={runtime === "claude" || kind === "anthropic-api" ? { id: "anthropic", name: "Anthropic" } : { id: "openai", name: "OpenAI" }} runtime={runtime} size={size} />;
}

/** The runtimes a profile runs, as small marks after its name (CC for Claude Code, Codex), and 自动决策 where it serves the automatic decisions. */
export function RuntimeTags({ runtimes, decision = false }: { runtimes: ("claude" | "codex")[]; decision?: boolean | undefined }) {
  return (
    <span className={waitingCss.runtimeTags}>
      {runtimes.map((r) => <Tip key={r} label={r === "claude" ? "Claude Code" : "Codex"}><span className={waitingCss.runtimeTag}><RuntimeLogo runtime={r} size={12} />{r === "claude" ? "CC" : "Codex"}</span></Tip>)}
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
  maker: Maker | null | undefined; runtime: "claude" | "codex"; badge: Badge | undefined; badgeText?: string | undefined; size?: number;
  wrap?: ((logo: ReactNode) => ReactNode) | undefined; children?: ReactNode;
}) {
  const logo = <ModelLogo maker={maker} runtime={runtime} size={Math.round(size * 0.62)} />;
  if (children == null) {
    return <span className={css.agentMark} style={{ "--mark": `${size}px` } as CSSProperties} data-badge={badge ?? undefined} role="img" aria-label={badgeText ?? undefined}>{logo}</span>;
  }
  return (
    <span className={`${css.agentMark} ${css.agentMarkJoined}`} style={{ "--mark": `${size}px` } as CSSProperties} data-badge={badge ?? undefined}>
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
      onClick={fixed ? undefined : (e) => { e.preventDefault(); e.stopPropagation(); flip(); }}>
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
 * transition lands on. `patience`: how long (ms) the new page is waited for at most. Plainly without the API or motion.
 * Resolves when it is over.
 */
export function transitionTo(go: () => void, ready?: () => boolean, patience = 800): Promise<void> {
  if (!document.startViewTransition || window.matchMedia("(prefers-reduced-motion: reduce)").matches) { go(); return Promise.resolve(); }
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
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) { go(); return Promise.resolve(); }
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
    await new Promise((resolve) => setTimeout(resolve, duration));
  }).finally(() => {
    begin();
    if (changing === now) changing = null;
  });
  return now.done;
}
