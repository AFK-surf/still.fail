// The narrow screen's small parts, as the Android app draws them (apps/android/…/ui/Parts.kt): model marks with their
// state badge, people's avatars, rings, segmented choices, navigation bars and list cards. Sizes are Android's, a dp
// or an sp a pixel here.
import { Fragment, useLayoutEffect, useRef, useState, type CSSProperties, type MouseEvent, type ReactNode } from "react";
import type { Badge as BadgeKind, Maker, Quota, RuntimeKind } from "../api.ts";
import { Check, ChevronLeft, Filter, Plug, Plus, Settings, type IconProps } from "@stillfail/ui/icons.tsx";
import { Mark as BrandMark, illustrationUrl } from "../brand.tsx";
import { ElsewhereLogo, SlackLogo } from "../ui.tsx";
import { MARKS, MONO } from "../modelMarks.ts";
import { QuotaBars } from "../components.tsx";
import { doingMatches, failed as itFailed, useDoing, useDoingFailed } from "../doing.ts";
import type { DoingItem } from "../core/shapes.ts";
import { useApp, useRootPage, type MenuItem } from "./app.tsx";
import * as css from "./parts.css.ts";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as barsCss from "./styles/bars.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as listsCss from "./styles/lists.css.ts";
import { t } from "../i18n.ts";
import { Spinner } from "@stillfail/ui/waiting.tsx";

const BASE = import.meta.env.BASE_URL;

/** The words for `key` with things drawn put in for their `{name}`s (a name in bold, a place), as `t` puts in text. */
export function tNodes(key: string, nodes: Record<string, ReactNode>, args?: Record<string, string | number>): ReactNode {
  return t(key, args).split(/(\{\w+\})/).map((part, i) => {
    const name = /^\{(\w+)\}$/.exec(part)?.[1];
    return name !== undefined && name in nodes ? <Fragment key={i}>{nodes[name]}</Fragment> : part;
  });
}

export type Icon = (props: IconProps) => ReactNode;

// ── model marks ────────────────────────────────────────────────────────


/** The mark of the company that made a model (the core says which); for one it does not know, its runtime's maker's (DeepSeek Harness's own; xAI's for Grok Build; Cursor's and Devin's own). */
export function MakerIcon({ maker, runtime, size }: { maker?: Maker | undefined; runtime?: RuntimeKind | string | undefined; size: number }) {
  const id = maker && MARKS.has(maker.id) ? maker.id : runtime === "codex" ? "openai" : runtime === "dsh" ? "dsh" : runtime === "grok" ? "xai" : runtime === "cursor" ? "cursor" : runtime === "devin" ? "devin" : "anthropic";
  return <img className={css.mMaker} src={`${BASE}models/${id}.svg`} alt={maker?.name ?? ""} width={size} height={size} data-mono={MONO.has(id) || undefined} />;
}

/** An agent's state as its mark shows it; done shows none. */
export type AgentState = "running" | "block" | "failed" | "done";

/** The core's badge (run | block | failed; none when done), as a state. */
export function stateOf(badge: BadgeKind | undefined): AgentState {
  return badge === "run" ? "running" : badge === "block" ? "block" : badge === "failed" ? "failed" : "done";
}

/** A state badge: solid orange = block, a still hollow orange ring = at work, red = failed; done has none. Nothing blinks. */
export function Badge({ state, size, ring, around, style }: { state: AgentState; size: number; ring: number; around: string; style?: CSSProperties }) {
  const r = size / 2;
  const inner = r - ring;
  const w = Math.min(2.5, inner);
  return (
    <svg className={css.mBadge} width={size} height={size} viewBox={`0 0 ${size} ${size}`} style={style} aria-hidden="true">
      <circle cx={r} cy={r} r={r} fill={around} />
      {state === "block" && <circle cx={r} cy={r} r={inner} fill="var(--m-accent)" />}
      {state === "failed" && <circle cx={r} cy={r} r={inner} fill="var(--m-red)" />}
      {state === "running" && <circle cx={r} cy={r} r={inner - w / 2} fill="none" stroke="var(--m-accent)" strokeWidth={w} />}
    </svg>
  );
}

/** An agent: its model maker's mark on a soft tile, with its state as a badge. */
export function ModelMark({ maker, runtime, size = 36, state, around = "var(--m-bg)" }: { maker?: Maker | undefined; runtime: RuntimeKind | string; size?: number; state?: AgentState | undefined; around?: string }) {
  const xs = size < 30;
  const badge = xs ? 11 : 15;
  return (
    <span className={css.mModelMark} style={{ width: size, height: size }}>
      <span className={css.mModelTile} style={{ borderRadius: `calc(${xs ? 6 : 11}px * ${vars.cornerScale})` }}>
        <MakerIcon maker={maker} runtime={runtime} size={Math.round(size * (xs ? 0.6 : 0.56))} />
      </span>
      {state && state !== "done" && <Badge state={state} size={badge} ring={xs ? 1.5 : 2} around={around} style={{ position: "absolute", right: -3, bottom: -3 }} />}
    </span>
  );
}

// ── people ─────────────────────────────────────────────────────────────

const AVATAR = ["#5877AE", "#248753", "#B9471F", "#8768AD", "#32818D", "#9A6F11"];

/** Java's String.hashCode, as Android picks an avatar's colour, so a person has the same colour on both. */
function javaHash(text: string): number {
  let h = 0;
  for (let i = 0; i < text.length; i++) h = (Math.imul(31, h) + text.charCodeAt(i)) | 0;
  return h;
}

export function avatarColor(id: string): string {
  const n = AVATAR.length;
  return AVATAR[((javaHash(id.toLowerCase()) % n) + n) % n]!;
}

export function initial(name: string): string {
  return ([...name.trim()][0] ?? "?").toUpperCase();
}

/** Their picture (a Google account's) once it is here; their initial on their colour until then, or without one. */
export function Avatar({ id, name, size, picture }: { id: string; name: string; size: number; picture?: string | undefined }) {
  const [failed, setFailed] = useState(false);
  return (
    <span className={css.mAvatar} style={{ width: size, height: size, background: avatarColor(id), fontSize: size * 0.5 }}>
      {picture && !failed
        ? <img src={picture} alt={name} referrerPolicy="no-referrer" onError={() => setFailed(true)} />
        : initial(name)}
    </span>
  );
}

/** A profile's allowance in a line: the PC's chips (QuotaBars), without their own tips (the row is what is tapped). */
export function QuotaRings({ quota }: { quota?: Quota | undefined }) {
  return <QuotaBars quota={quota} compact bare />;
}

/** Whose service a profile runs on: Anthropic, OpenAI or xAI for a subscription or a key, OpenCode for OpenCode Go. */
export function ProviderMark({ runtime, kind, mark, size = 16 }: { runtime: string; kind?: string | undefined; mark?: string | null | undefined; size?: number }) {
  if (kind === "opencode-go" || mark === "opencode") {
    return (
      <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden="true" className="m-provider">
        <rect x="6" y="4" width="12" height="16" fill="none" stroke="var(--m-ink)" strokeWidth="2.4" />
      </svg>
    );
  }
  // A key on a listed provider: its maker's mark, or the generic plug where there is none.
  if (kind === "api-provider") return mark && MARKS.has(mark) ? <MakerIcon maker={{ id: mark, name: mark }} runtime={runtime} size={size} /> : <Plug size={size} strokeWidth={1.7} aria-hidden="true" />;
  const maker = runtime === "claude" || kind === "anthropic-api" ? { id: "anthropic", name: "Anthropic" } : runtime === "grok" ? { id: "xai", name: "xAI" } : runtime === "cursor" ? { id: "cursor", name: "Cursor" } : runtime === "devin" ? { id: "devin", name: "Devin" } : { id: "openai", name: "OpenAI" };
  return <MakerIcon maker={maker} runtime={runtime} size={size} />;
}

// ── controls ───────────────────────────────────────────────────────────

/**
 * A segmented choice: a track that tints whatever it sits on (the text colour at 6%), and a light thumb that slides to
 * the chosen option. Without `track` what it sits in (a capsule) is its track.
 */
export function Seg({ options, selected, onSelect, height = 30, fill = false, radius = 10, inset = 2, track = true, className }: {
  options: string[]; selected: number; onSelect: (i: number) => void; height?: number; fill?: boolean; radius?: number; inset?: number; track?: boolean; className?: string;
}) {
  const row = useRef<HTMLDivElement>(null);
  const [thumb, setThumb] = useState<{ x: number; w: number; moved: boolean } | null>(null);
  // A capsule stays round; a rounded rectangle takes the smooth corner over the longer radius.
  const smooth = radius * 2 < height;
  useLayoutEffect(() => {
    const el = row.current?.querySelectorAll<HTMLElement>(`.${css.mSegOption}`)[selected];
    if (!el) return;
    // The first placement jumps; a change of choice slides.
    setThumb((t) => ({ x: el.offsetLeft, w: el.offsetWidth, moved: t !== null }));
    // Filling and short of room, the options scroll sideways (parts.css.ts mSeg): the chosen one brought into view, as
    // little as that takes.
    const box = row.current?.parentElement;
    if (fill && box) {
      const left = el.offsetLeft;
      const right = left + el.offsetWidth + 2 * inset;
      if (left < box.scrollLeft) box.scrollLeft = left;
      else if (right > box.scrollLeft + box.clientWidth) box.scrollLeft = right - box.clientWidth;
    }
  }, [selected, options.length, fill, inset]);
  return (
    <div className={`${css.mSeg}${className ? ` ${className}` : ""}`} data-track={track || undefined} data-fill={fill || undefined}
      data-smooth={smooth || undefined} style={{ height, borderRadius: smooth ? `calc(${radius}px * ${vars.cornerScale})` : radius, padding: inset }}>
      <div className={css.mSegRow} ref={row}>
        {thumb && <span className={css.mSegThumb} data-moved={thumb.moved || undefined}
          style={{ transform: `translateX(${thumb.x}px)`, width: thumb.w, borderRadius: smooth ? `calc(${radius}px * ${vars.cornerScale} - ${inset}px)` : Math.max(0, radius - inset) }} />}
        {options.map((label, i) => (
          <button key={label} type="button" className={css.mSegOption} data-on={i === selected || undefined} onClick={() => onSelect(i)}>{label}</button>
        ))}
      </div>
    </div>
  );
}

// ── navigation ─────────────────────────────────────────────────────────

/** Back, in the accent colour, with where it goes back to. */
/** What was asked failed a moment ago (`error`, why): a small red mark; tapped, it says why (and not the row's own tap). */
export function FailedMark({ error, size = 14 }: { error: string; size?: number }) {
  const app = useApp();
  return (
    <span role="img" className={css.mFailed} style={{ width: size, height: size, fontSize: size - 4 }} aria-label={t("web-mobile.parts.failedWhy", { error })} title={error}
      onClick={(e) => { e.preventDefault(); e.stopPropagation(); app.toast(error); }}>!</span>
  );
}

/** Why one of `calls` about what `on` names failed a moment ago, in `doing` (../doing.ts useDoingList, read once for many
 *  rows); undefined when none did. As useDoingFailed. */
export function failedIn(doing: readonly DoingItem[], calls: string | readonly string[], on: Parameters<typeof doingMatches>[2]): string | undefined {
  const item = doing.findLast((d) => itFailed(d) && doingMatches(d, calls, on));
  return item ? (item.error ?? t("web-mobile.parts.failed")) : undefined;
}

/** Where `calls` about what `on` names stand on this device (../doing.ts): a spinner while under way, the failure mark a few
 *  seconds after one failed, nothing otherwise. For a row whose menu or sheet that asked it may be closed by then. */
export function DoingMark({ calls, on, inline = false, onColor = false }: { calls: string | readonly string[]; on?: Parameters<typeof useDoing>[1]; inline?: boolean; onColor?: boolean }) {
  const running = useDoing(calls, on);
  const error = useDoingFailed(calls, on);
  return running ? <Spinner inline={inline} className={onColor ? partsCss.mSpinOnColor : undefined} /> : error !== undefined ? <FailedMark error={error} size={inline ? 12 : 14} /> : null;
}

export function NavBack({ label, onClick }: { label: ReactNode; onClick: () => void }) {
  // A place's top page (the bottom bar under it) has nowhere to go back to: its room kept, nothing drawn in it.
  if (useRootPage()) return <span className={css.mNavBack} aria-hidden="true" style={{ visibility: "hidden" }}><ChevronLeft size={22} /></span>;
  return <button type="button" className={css.mNavBack} onClick={onClick}><ChevronLeft size={22} /><span className={css.mNavBackWord}>{label}</span></button>;
}

/** A bar's button: the icon alone, no disc behind it (a bar's buttons are quiet). */
export function NavButton({ icon: I, onClick, iconSize = 18, label }: { icon: Icon; onClick: () => void; iconSize?: number; label: string }) {
  return <button type="button" className={barsCss.mNavButton} onClick={onClick} aria-label={label}><I size={iconSize} /></button>;
}

/** A page's compact bar: back, a centred title, and one action. No line under it: the page's paper runs on. */
export function NavBar({ back, onBack, title, sub, trailing }: { back: ReactNode; onBack: () => void; title: string; sub?: ReactNode; trailing?: ReactNode }) {
  return (
    <header className={css.mNavbar}>
      <span className={css.mNavbarBack}><NavBack label={back} onClick={onBack} /></span>
      <span className={css.mNavbarTitle}><b>{title}</b>{sub !== undefined && <span className={css.mNavbarSub}>{sub}</span>}</span>
      {trailing !== undefined && <span className={css.mNavbarTrailing}>{trailing}</span>}
    </header>
  );
}

/** Back to the chats, at the top of a large-title page. */
export function TopBack({ label, onBack, trailing }: { label: string; onBack: () => void; trailing?: ReactNode }) {
  return <div className={`${css.mTopBack} ${trailing !== undefined ? css.mTopBackRow : ""}`}><NavBack label={label} onClick={onBack} />{trailing}</div>;
}

/** A place's primary action (placeActions.tsx): in the bottom bar's notch on its top page, at its head's end when pushed. */
export interface PlaceAction { key: string; label: string; run: () => void }

/**
 * A place's page's head (文件, Station, Profile, 连接, 用量, 已归档). Its top page, the bottom bar under it: Home's
 * top bar, the gear to the settings and the page's name, what else it does at its end (its primary action is in the
 * bar's notch). Opened from elsewhere (the settings, a link): a page like any other, back to where it came from, with
 * its primary action at its end too.
 */
export function PlaceHead({ title, back, onBack, trailing, primary }: {
  title: string; back: string; onBack: () => void; trailing?: ReactNode; primary?: PlaceAction | null | undefined;
}) {
  const app = useApp();
  if (!useRootPage()) {
    const plus = primary ? <NavButton icon={Plus} iconSize={20} label={primary.label} onClick={primary.run} /> : null;
    return <NavBar back={back} onBack={onBack} title={title} trailing={trailing || plus ? <>{trailing}{plus}</> : undefined} />;
  }
  return (
    <header className={`${css.mPlaceHead} ${pagesCss.mGlass}`}>
      <button type="button" className={barsCss.mNavButton} onClick={() => app.push(app.at("/settings"))} aria-label={t("web-mobile.settings.title")}>
        <Settings size={22} />
      </button>
      <h1 className={css.mPlaceTitle}>{title}</h1>
      {trailing}
    </header>
  );
}

/** What a place is, said where its list would be while that has nothing (its top page says it nowhere else). */
export function PlaceNote({ children }: { children: ReactNode }) {
  return <p className={css.mPlaceNote}>{children}</p>;
}

/** A choice of a filter's menu, ticked when it is the one; the others keep its room. */
export const ticked = (on: boolean) => (on ? <Check size={16} /> : <span style={{ width: 16 }} />);

/**
 * A list's filter in a head (the chats', the connects'): its icon, in the accent while it narrows the list (`on`);
 * tapped, its menu under it (`items`, the one chosen ticked). `label` says what it is set to.
 */
export function FilterMenu({ on, label, items }: { on: boolean; label: string; items: MenuItem[] }) {
  const app = useApp();
  return (
    <button type="button" className={`${barsCss.mNavButton} ${css.mFilterMenu}`} data-on={on || undefined} aria-label={label}
      onClick={(e) => {
        const r = e.currentTarget.getBoundingClientRect();
        // The menu is 180 wide (app.tsx MenuHost): its right edge under the button's.
        app.menu({ anchor: new DOMRect(r.right - 180, r.top, 0, r.height), items });
      }}>
      <Filter size={20} />
    </button>
  );
}

/** A page's large title (stations, settings): a small line over a big word. */
export function LargeTitle({ small, big }: { small: string; big: string }) {
  return <div className={css.mLargeTitle}><span>{small}</span><h1>{big}</h1></div>;
}

// ── lists and cards ────────────────────────────────────────────────────

/** A section's title; `mark`: what it holds at a glance (a vendor's mark), before it. */
export function SectionHeader({ title, trailing, start = 20, mark }: { title: ReactNode; trailing?: string | undefined; start?: number; mark?: ReactNode }) {
  return (
    <div className={css.mSection} style={{ paddingLeft: start }}>
      {mark && <span className={css.mSectionMark} aria-hidden="true">{mark}</span>}<b>{title}</b>{trailing !== undefined && <span>{trailing}</span>}
    </div>
  );
}

export function Card({ onClick, children }: { onClick?: () => void; children: ReactNode }) {
  return onClick
    ? <button type="button" className={listsCss.mCard} onClick={onClick}>{children}</button>
    : <div className={listsCss.mCard}>{children}</div>;
}

/** Rows on one rounded card; the card groups them, no lines between. */
export function ListCard({ children }: { children: ReactNode }) {
  return <div className={css.mListCard}>{children}</div>;
}

export function ListRow({ onClick, children }: { onClick?: (() => void) | undefined; children: ReactNode }) {
  return onClick
    ? <button type="button" className={css.mListRow} onClick={onClick}>{children}</button>
    : <div className={css.mListRow}>{children}</div>;
}

/** A row of a picking sheet: what, a line under it, two short notes at its end (each by one of those lines), and a check on the chosen one. */
/** `mark`: a small mark after the label (what a workspace has waiting); `busy`: what it asked is under way (a spinner at its end, not pressed again);
 *  `failed`: why what it asked failed a moment ago (the failure mark at its end). */
/// `done`: what it stands for is done (a station joined): not picked again, its ink kept, a green check at its end.
export function PickRow({ label, sub, aside, checked = false, enabled = true, busy = false, done = false, failed, accent = false, leading, mark, onClick }: {
  label: string; sub?: string | undefined; aside?: [string, string]; checked?: boolean; enabled?: boolean; busy?: boolean; done?: boolean; failed?: string | undefined; accent?: boolean; leading?: ReactNode; mark?: ReactNode; onClick: () => void;
}) {
  const title = mark ? <span className={css.mPickLabel}><span className={css.mPickLabelText}>{label}</span>{mark}</span> : <span>{label}</span>;
  return (
    <button type="button" className={css.mPickRow} disabled={!enabled || busy || done} data-accent={accent || undefined} data-busy={busy || undefined} data-done={done || undefined} aria-busy={busy || undefined} onClick={onClick}>
      {leading}
      {aside === undefined
        ? <span className={css.mPickText}>{title}{sub !== undefined && <small>{sub}</small>}</span>
        : (
          <span className={`${css.mPickText} ${css.mPickGrid}`}>
            {title}<small className={css.mPickAside}>{aside[0]}</small>
            {sub !== undefined ? <small>{sub}</small> : <span />}<small className={css.mPickAside}>{aside[1]}</small>
          </span>
        )}
      {busy ? <Spinner inline /> : failed !== undefined ? <FailedMark error={failed} /> : done ? <Check size={14} className={css.mPickDone} /> : checked && <Check size={14} className={partsCss.mAccent} />}
    </button>
  );
}

export function GroupLabel({ children }: { children: ReactNode }) {
  return <div className={listsCss.mGroupLabel}>{children}</div>;
}

export function InfoList({ children }: { children: ReactNode }) {
  return <div className={css.mInfoList}>{children}</div>;
}

/** `busy`: what it asked is under way (a spinner at its end, not pressed again); `failed`: why it failed a moment ago (the failure mark there). */
export function InfoRow({ onClick, busy = false, failed, children }: { onClick?: (e: MouseEvent<HTMLButtonElement>) => void; busy?: boolean; failed?: string | undefined; children: ReactNode }) {
  return onClick
    ? (
      <button type="button" className={listsCss.mInfoRow} disabled={busy} aria-busy={busy || undefined} onClick={onClick}>
        {children}{busy ? <Spinner inline /> : failed !== undefined && <FailedMark error={failed} />}
      </button>
    )
    : <div className={listsCss.mInfoRow}>{children}</div>;
}

/** A line to type in, on a soft frame. */
export function Field({ value, onChange, placeholder, mono = false }: { value: string; onChange: (v: string) => void; placeholder: string; mono?: boolean }) {
  return <input className={listsCss.mField} data-mono={mono || undefined} value={value} placeholder={placeholder} maxLength={mono ? 32 : 80} onChange={(e) => onChange(e.target.value)} spellCheck={false} />;
}

export function Button({ label, primary, busy = false, enabled = true, onClick }: { label: string; primary: boolean; busy?: boolean; enabled?: boolean; onClick: () => void }) {
  return (
    <button type="button" className={css.mButton} data-primary={primary || undefined} disabled={!enabled || busy} onClick={onClick}>
      {busy && <Spinner className={primary ? partsCss.mSpinOnColor : undefined} />}{label}
    </button>
  );
}

/** A link's button (in the accent, no frame); `busy`: what it asked is under way, a spinner before its words, not pressed again;
 *  `failed`: why it failed a moment ago (the failure mark before its words). */
export function LinkButton({ label, busy = false, failed, enabled = true, className, onClick }: {
  label: ReactNode; busy?: boolean; failed?: string | undefined; enabled?: boolean; className?: string; onClick: () => void;
}) {
  return (
    <button type="button" className={`${partsCss.mLink} ${css.mLinkButton}${className ? ` ${className}` : ""}`} disabled={!enabled || busy} aria-busy={busy || undefined} onClick={onClick}>
      {busy ? <Spinner inline /> : failed !== undefined && <FailedMark error={failed} size={12} />}{label}
    </button>
  );
}

/** What a page says where its body would be when what it shows is not there (not found, no station); a wait is a
 *  `Waiting` (@stillfail/ui waiting.tsx). */
export function Gone({ text }: { text: string }) {
  return <div className={css.mGone}>{text}</div>;
}

export function Mark({ size = 14 }: { size?: number }) {
  return <BrandMark size={size} />;
}

/** `kind`: where it is (a connect's kind, a place's surface): Feishu's mark for Feishu, else Slack's. */
export function SlackMark({ size = 13, kind }: { size?: number; kind?: string | null | undefined }) {
  return kind ? <ElsewhereLogo kind={kind} size={size} /> : <SlackLogo size={size} />;
}

/** A scene beside text that says the same (Android's illustrations, as the web has them). */
export function Illustration({ name, width }: { name: "new-chat" | "station-offline" | "sign-in"; width: number }) {
  // Decoded as the app starts (../brand.tsx), drawn in its first frame.
  return <img className={partsCss.mIllus} src={illustrationUrl(name)} alt="" width={width} decoding="sync" />;
}
