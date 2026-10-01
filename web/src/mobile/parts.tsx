// The narrow screen's small parts, as the Android app draws them (apps/android/…/ui/Parts.kt): model marks with their
// state badge, people's avatars, rings, segmented choices, navigation bars and list cards. Sizes are Android's, a dp
// or an sp a pixel here.
import { useLayoutEffect, useRef, useState, type CSSProperties, type ReactNode } from "react";
import type { Badge as BadgeKind, Maker, Quota, RuntimeKind } from "../api.ts";
import { Check, ChevronLeft, type IconProps } from "../icons.tsx";
import { Mark as BrandMark, illustrationUrl } from "../brand.tsx";
import { SlackLogo } from "../ui.tsx";
import { QuotaBars } from "../components.tsx";
import * as css from "./parts.css.ts";
import * as waitingCss from "../styles/waiting.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as barsCss from "./styles/bars.css.ts";
import * as listsCss from "./styles/lists.css.ts";

const BASE = import.meta.env.BASE_URL;

export type Icon = (props: IconProps) => ReactNode;

// ── model marks ────────────────────────────────────────────────────────

const MAKERS = new Set(["anthropic", "openai", "deepseek", "qwen", "zhipu", "gemini", "kimi", "minimax", "xai"]);
/** Marks of one colour, drawn in the page's ink. */
const MONO = new Set(["anthropic", "openai", "kimi", "xai"]);

/** The mark of the company that made a model (the core says which); for one it does not know, its runtime's maker's. */
export function MakerIcon({ maker, runtime, size }: { maker?: Maker | undefined; runtime?: RuntimeKind | string | undefined; size: number }) {
  const id = maker && MAKERS.has(maker.id) ? maker.id : runtime === "codex" ? "openai" : "anthropic";
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
      <span className={css.mModelTile} style={{ borderRadius: xs ? 6 : 11 }}>
        <MakerIcon maker={maker} runtime={runtime} size={Math.round(size * (xs ? 0.6 : 0.56))} />
      </span>
      {state && state !== "done" && <Badge state={state} size={badge} ring={xs ? 1.5 : 2} around={around} style={{ position: "absolute", right: -3, bottom: -3 }} />}
    </span>
  );
}

// ── people ─────────────────────────────────────────────────────────────

const AVATAR = ["#5B7BB2", "#2F8F5B", "#B9471F", "#8A6BB0", "#3F8C99", "#B0842F"];

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

/** Whose service a profile runs on: Anthropic or OpenAI for a subscription or a key, OpenCode for OpenCode Go. */
export function ProviderMark({ runtime, kind, size = 16 }: { runtime: string; kind?: string | undefined; size?: number }) {
  if (kind === "opencode-go") {
    return (
      <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden="true" className="m-provider">
        <rect x="6" y="4" width="12" height="16" fill="none" stroke="var(--m-ink)" strokeWidth="2.4" />
      </svg>
    );
  }
  const maker = runtime === "claude" || kind === "anthropic-api" ? { id: "anthropic", name: "Anthropic" } : { id: "openai", name: "OpenAI" };
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
  useLayoutEffect(() => {
    const el = row.current?.querySelectorAll<HTMLElement>(`.${css.mSegOption}`)[selected];
    if (!el) return;
    // The first placement jumps; a change of choice slides.
    setThumb((t) => ({ x: el.offsetLeft, w: el.offsetWidth, moved: t !== null }));
  }, [selected, options.length]);
  return (
    <div className={`${css.mSeg}${className ? ` ${className}` : ""}`} data-track={track || undefined} data-fill={fill || undefined}
      style={{ height, borderRadius: radius, padding: inset }}>
      <div className={css.mSegRow} ref={row}>
        {thumb && <span className={css.mSegThumb} data-moved={thumb.moved || undefined}
          style={{ transform: `translateX(${thumb.x}px)`, width: thumb.w, borderRadius: Math.max(0, radius - inset) }} />}
        {options.map((label, i) => (
          <button key={label} type="button" className={css.mSegOption} data-on={i === selected || undefined} onClick={() => onSelect(i)}>{label}</button>
        ))}
      </div>
    </div>
  );
}

/** The wide screen's spinner (../styles/waiting.css.ts), at a size; `color`, its turning part's (on a dark ground). */
export function Spinner({ size, color }: { size: number; color?: string }) {
  return <span className={`${waitingCss.spinner} ${css.mSpinner}`} style={{ width: size, height: size, borderWidth: size < 14 ? 1.5 : 2, ...(color ? { borderTopColor: color } : {}) }} aria-hidden="true" />;
}

// ── navigation ─────────────────────────────────────────────────────────

/** Back, in the accent colour, with where it goes back to. */
export function NavBack({ label, onClick }: { label: string; onClick: () => void }) {
  return <button type="button" className={css.mNavBack} onClick={onClick}><ChevronLeft size={22} />{label}</button>;
}

/** A bar's button: the icon alone, no disc behind it (a bar's buttons are quiet). */
export function NavButton({ icon: I, onClick, iconSize = 18, label }: { icon: Icon; onClick: () => void; iconSize?: number; label: string }) {
  return <button type="button" className={barsCss.mNavButton} onClick={onClick} aria-label={label}><I size={iconSize} /></button>;
}

/** A page's compact bar: back, a centred title, and one action. No line under it: the page's paper runs on. */
export function NavBar({ back, onBack, title, sub, trailing }: { back: string; onBack: () => void; title: string; sub?: ReactNode; trailing?: ReactNode }) {
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

/** A page's large title (stations, settings): a small line over a big word. */
export function LargeTitle({ small, big }: { small: string; big: string }) {
  return <div className={css.mLargeTitle}><span>{small}</span><h1>{big}</h1></div>;
}

// ── lists and cards ────────────────────────────────────────────────────

export function SectionHeader({ title, trailing, start = 20 }: { title: string; trailing?: string | undefined; start?: number }) {
  return <div className={css.mSection} style={{ paddingLeft: start }}><b>{title}</b>{trailing !== undefined && <span>{trailing}</span>}</div>;
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
/** `mark`: a small mark after the label (what a workspace has waiting); `busy`: what it asked is under way (a spinner at its end, not pressed again). */
export function PickRow({ label, sub, aside, checked = false, enabled = true, busy = false, accent = false, leading, mark, onClick }: {
  label: string; sub?: string | undefined; aside?: [string, string]; checked?: boolean; enabled?: boolean; busy?: boolean; accent?: boolean; leading?: ReactNode; mark?: ReactNode; onClick: () => void;
}) {
  const title = mark ? <span className={css.mPickLabel}><span className={css.mPickLabelText}>{label}</span>{mark}</span> : <span>{label}</span>;
  return (
    <button type="button" className={css.mPickRow} disabled={!enabled || busy} data-accent={accent || undefined} data-busy={busy || undefined} aria-busy={busy || undefined} onClick={onClick}>
      {leading}
      {aside === undefined
        ? <span className={css.mPickText}>{title}{sub !== undefined && <small>{sub}</small>}</span>
        : (
          <span className={`${css.mPickText} ${css.mPickGrid}`}>
            {title}<small className={css.mPickAside}>{aside[0]}</small>
            {sub !== undefined ? <small>{sub}</small> : <span />}<small className={css.mPickAside}>{aside[1]}</small>
          </span>
        )}
      {busy ? <Spinner size={14} /> : checked && <Check size={14} className={partsCss.mAccent} />}
    </button>
  );
}

export function GroupLabel({ children }: { children: ReactNode }) {
  return <div className={listsCss.mGroupLabel}>{children}</div>;
}

export function InfoList({ children }: { children: ReactNode }) {
  return <div className={css.mInfoList}>{children}</div>;
}

/** `busy`: what it asked is under way (a spinner at its end, not pressed again). */
export function InfoRow({ onClick, busy = false, children }: { onClick?: () => void; busy?: boolean; children: ReactNode }) {
  return onClick
    ? <button type="button" className={listsCss.mInfoRow} disabled={busy} aria-busy={busy || undefined} onClick={onClick}>{children}{busy && <Spinner size={14} />}</button>
    : <div className={listsCss.mInfoRow}>{children}</div>;
}

/** A line to type in, on a soft frame. */
export function Field({ value, onChange, placeholder, mono = false }: { value: string; onChange: (v: string) => void; placeholder: string; mono?: boolean }) {
  return <input className={listsCss.mField} data-mono={mono || undefined} value={value} placeholder={placeholder} maxLength={mono ? 32 : 80} onChange={(e) => onChange(e.target.value)} spellCheck={false} />;
}

export function Button({ label, primary, busy = false, enabled = true, onClick }: { label: string; primary: boolean; busy?: boolean; enabled?: boolean; onClick: () => void }) {
  return (
    <button type="button" className={css.mButton} data-primary={primary || undefined} disabled={!enabled || busy} onClick={onClick}>
      {busy && <Spinner size={14} />}{label}
    </button>
  );
}

/** A link's button (in the accent, no frame); `busy`: what it asked is under way, a spinner before its words, not pressed again. */
export function LinkButton({ label, busy = false, enabled = true, className, onClick }: { label: ReactNode; busy?: boolean; enabled?: boolean; className?: string; onClick: () => void }) {
  return (
    <button type="button" className={`${partsCss.mLink} ${css.mLinkButton}${className ? ` ${className}` : ""}`} disabled={!enabled || busy} aria-busy={busy || undefined} onClick={onClick}>
      {busy && <Spinner size={13} />}{label}
    </button>
  );
}

/** Something is on its way: said in words, centred on the page. */
export function Loading({ text }: { text: string }) {
  return <div className={css.mLoading}>{text}</div>;
}

export function Mark({ size = 14 }: { size?: number }) {
  return <BrandMark size={size} />;
}

export function SlackMark({ size = 13 }: { size?: number }) {
  return <SlackLogo size={size} />;
}

/** A scene beside text that says the same (Android's illustrations, as the web has them). */
export function Illustration({ name, width }: { name: "new-chat" | "station-offline" | "sign-in"; width: number }) {
  // Decoded as the app starts (../brand.tsx), drawn in its first frame.
  return <img className={partsCss.mIllus} src={illustrationUrl(name)} alt="" width={width} decoding="sync" />;
}
