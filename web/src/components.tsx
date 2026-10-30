// Small pieces the pages share.
import { useAppearance } from "./theme.ts";
import { useRef, type ComponentProps, type ReactNode } from "react";
import type { Level, PersonShown, Quota } from "./api.ts";
import type { Meter } from "./core/shapes.ts";
import { useOnlyMine, useSidebarMode, type SidebarMode } from "./station.tsx";
import { Segmented, Tip } from "./ui.tsx";
import { Check, Filter } from "@stillfail/ui/icons.tsx";
import { useLocation, useNavigate } from "react-router";
import { DropdownMenu } from "radix-ui";
import * as controlsCss from "@stillfail/ui/styles/controls.css.ts";
import * as css from "./components.css.ts";
import * as cloudCss from "./styles/cloud.css.ts";
import * as shellCss from "./styles/shell.css.ts";
import { t } from "./i18n.ts";
import { tx } from "./cloud/words.tsx";

/**
 * A filter: 全部 or only the viewer's (我参与的 for chats, 我创建的 for connects), from a menu; for chats (`watching`)
 * also the watching ones (监控中). `compact`: a filter button alone, never marked for what it shows; else the filter's name
 * beside it. `archive` (已归档, the archive's page, under a line): the list the sidebar shows in place of the chats, with
 * a page of its own; another list picked there goes back to the chats (`chats`). Its words are the chats' with
 * `watching`, else the connects' (`label` and `mine`, which named them, are no longer read).
 */
export function MineFilter({ compact, archive, watching, chats }: { label?: string; mine?: string; compact?: boolean; archive?: string | undefined; watching?: boolean; chats?: string }) {
  const [onlyMine, setOnlyMine] = useOnlyMine();
  const [mode, setMode] = useSidebarMode();
  // Chats: one of three (the core keeps 我参与的 and 监控中 apart), or the archive in their place; connects: all or mine.
  const shown = mode === "archive" && !archive ? "all" : mode;
  const filter: SidebarMode = watching ? shown : onlyMine ? "mine" : "all";
  const setFilter = (value: SidebarMode) => watching ? setMode(value) : setOnlyMine(value === "mine");
  const of = watching ? "chats" : "connects";
  const mine = t(`web-main.filter.${of}.mine`);
  const named = filter === "archive" ? t("web-main.filter.archived")
    : filter === "mine" ? mine : filter === "watching" ? t("web-main.filter.watching") : t("web-main.filter.all");
  const navigate = useNavigate();
  const path = useLocation().pathname;
  // Gone to another page, the focus is not brought back to the button (it would be ringed there, over the page left).
  const leaving = useRef(false);
  const item = (value: SidebarMode, text: string) => (
    <DropdownMenu.Item className={`${controlsCss.menuItem} ${controlsCss.chooserItem}`} onSelect={() => {
      setFilter(value);
      const to = value === "archive" ? archive : path === archive ? chats : undefined;
      if (to && to !== path) { leaving.current = true; navigate(to); }
    }}>
      <span className={controlsCss.chooserCheck}>{filter === value && <Check size={14} />}</span>{text}
    </DropdownMenu.Item>
  );
  return (
    <DropdownMenu.Root modal={false}>
      <Tip label={t(`web-main.filter.${of}`)}><DropdownMenu.Trigger className={compact ? css.mineFilterBtn : `${css.mineFilterBtn} ${css.mineFilterWide}`} aria-label={t(`web-main.filter.${of}.named`, { named })}>
        <Filter size={16} strokeWidth={1.8} />{!compact && <span>{named}</span>}
      </DropdownMenu.Trigger></Tip>
      <DropdownMenu.Portal>
        <DropdownMenu.Content className={`${controlsCss.popover} ${controlsCss.menuList} ${controlsCss.chooserMenu}`} align="end" sideOffset={6} collisionPadding={8}
          onCloseAutoFocus={(e) => { if (leaving.current) { leaving.current = false; e.preventDefault(); } }}>
          {item("all", t(`web-main.filter.${of}.all`))}
          {item("mine", mine)}
          {watching && item("watching", t("web-main.filter.watching"))}
          {archive && <>
            <DropdownMenu.Separator className={controlsCss.menuSep} />
            {item("archive", t("web-main.filter.archived"))}
          </>}
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  );
}

/**
 * "由 X 创建": the person as the core names them (你 for the viewer). `verb`: created (a connect), or started (a chat;
 * "发起", as it was given before).
 */
export function CreatorText({ creator, verb = "created" }: { creator: { via?: string | null; shown?: PersonShown } | null | undefined; verb?: "created" | "started" }) {
  if (!creator?.shown) return null;
  const said = verb === "created" ? "created" : "started";
  const key = `web-main.creator.${said}${creator.via === "slack" ? ".slack" : creator.via === "feishu" ? ".feishu" : ""}`;
  return <span className={css.creator}>{tx(key, { name: <PersonNamed name={creator.shown.display} picture={creator.shown.picture} /> })}</span>;
}

/** A person's picture, round, at `size`: their account's, else their first letter. */
export function PersonFace({ name, picture, size = 16 }: { name: string; picture?: string | null | undefined; size?: number }) {
  return picture
    ? <img className={cloudCss.person} src={picture} alt="" width={size} height={size} referrerPolicy="no-referrer" />
    : <span className={`${cloudCss.person} ${cloudCss.personLetter}`} style={{ width: size, height: size, fontSize: Math.round(size * 0.56) }} aria-hidden="true">{([...name.trim()][0] ?? "?").toUpperCase()}</span>;
}

/** A person named: their picture (PersonFace), then their name (or `children` in its place). */
export function PersonNamed({ name, picture, size = 16, children }: { name: string; picture?: string | null | undefined; size?: number; children?: ReactNode }) {
  return <span className={css.person}><PersonFace name={name} picture={picture} size={size} />{children ?? name}</span>;
}

/** Who a connect belongs to: avatar and name as the core names them. */
export function OwnerLabel({ owner }: { owner: { id: string; shown?: PersonShown } | null | undefined }) {
  if (!owner?.shown) return <span className={`${css.owner} ${css.ownerNone}`}>{t("web-main.owner.none")}</span>;
  const { name, picture, mine } = owner.shown;
  return (
    <Tip label={owner.id === "local" ? undefined : owner.id}><span className={css.owner}>
      <PersonFace name={name} picture={picture} />
      {mine ? t("web-main.owner.you", { name }) : name}
    </span></Tip>
  );
}

/**
 * A profile's allowance, as the core puts its windows (shortest first, each marked): compact, a rounded box per window
 * (QuotaChip); else each window's number large over its cells (Dial). `small`: where a line is lower than a row (the
 * model control).
 */
export function QuotaBars({ quota, compact, small, bare }: { quota: Quota | null | undefined; compact?: boolean; small?: boolean; bare?: boolean }) {
  if (!quota) return compact ? null : <p className={`${shellCss.muted} ${css.quotaNote}`}>{t("web-main.quota.unchecked")}</p>;
  if (quota.state !== "ok" || quota.windows.length === 0) return compact ? null : <p className={`${shellCss.muted} ${css.quotaNote}`}>{quota.detail ?? t("web-main.quota.unknown")}</p>;
  if (compact) {
    return (
      <span className={css.quotaChips}>
        {quota.windows.map((w) => (
          // Bare: inside a control, so not a stop of their own for the keyboard; the tip still shows on hover.
          <Tip key={w.label} label={<>{quotaLeft(w)}{w.refills && <><br />{w.refills}</>}</>}>
            <QuotaChip window={w} marked={quota.windows.length > 1} small={small} bare={bare} />
          </Tip>
        ))}
      </span>
    );
  }
  // The profile's own page: each window's number large, its cells, its name and when it refills.
  return (
    <div className={css.quotaDials}>
      {quota.windows.map((w) => <Dial key={w.label} number={String(w.left)} unit="%" fill={leftOf(w.left)} level={w.level} label={w.label} note={w.refills} aria={quotaLeft(w)} />)}
    </div>
  );
}

// How far a box is filled or its cells lit, decided here for all of them, as each is read: an allowance as a battery,
// as far as is left (what it says); a machine's CPU, memory or disk as a disk's bar, as far as is used (100 less what
// is left), so that a fuller one means less room though its words say what is left.
const leftOf = (left: number) => Math.max(0, Math.min(100, left));
const usedOf = (left: number) => 100 - leftOf(left);

/** A figure large (what is left), ten cells lit as far as `fill` (0–100) in the colour of its level, its name and a
 * quiet note under: an allowance's window on its profile's page, a machine's CPU, memory or disk on its own. */
function Dial({ number, unit, fill, level, label, note, aria }: { number: string; unit: string; fill: number; level: Level | string; label: string; note: string | null | undefined; aria: string }) {
  const lit = Math.round(fill / 10);
  return (
    <div className={css.quotaDial} data-level={level}>
      <span className={css.quotaDialNumber}>{number}<small>{unit}</small></span>
      <span className={css.quotaDialCells} role="img" aria-label={aria}>
        {Array.from({ length: 10 }, (_, i) => <i key={i} data-on={i < lit || undefined} />)}
      </span>
      <span className={css.quotaDialLabel}>{label}</span>
      <span className={css.quotaDialReset}>{note ?? "\u00a0"}</span>
    </div>
  );
}

/** A machine's CPU, memory and disk on its own page (a station's details): as an allowance's windows on its profile's,
 * each what is left large over its cells. `row`: the three across the width however narrow (the phone's page). */
export function MeterDials({ meters, row = false }: { meters: Meter[]; row?: boolean }) {
  return <div className={css.quotaDials} data-row={row || undefined}>{meters.map((m) => <Dial key={m.label} number={m.big} unit={m.unit} fill={usedOf(m.left)} level={m.level} label={m.title} note={m.total} aria={`${m.title} ${m.big} ${m.unit}`} />)}</div>;
}

type ChipProps = { small?: boolean | undefined; bare?: boolean | undefined } & Omit<ComponentProps<"span">, "children">;

/** A rounded box with a figure in it (its mark before it, when given) and its ground filled from the left as far as
 * `fill` (0–100): grey while there is plenty, in the colour of the core's `level` once it runs low; as level `progress`,
 * in the accent, its fill moving smoothly to each new share. What else it is given (a tip's trigger props and ref) goes
 * on the box. Drawn only through QuotaChip, MeterChip and ProgressChip, which say how full. */
function FillChip({ fill, level, mark, label, text, small, bare, ...rest }: { fill: number; level: Level | string; mark?: ReactNode; label: string; text: string } & ChipProps) {
  return (
    <span {...rest} className={css.quotaChip} data-level={level} data-small={small || undefined} tabIndex={bare ? undefined : 0} role="img" aria-label={label}>
      <i className={css.quotaChipFill} style={{ width: `${Math.max(0, Math.min(100, fill))}%` }} aria-hidden="true" />
      <span className={css.quotaChipText}>{mark != null && <span className={css.quotaChipMark}>{mark}</span>}<span>{text}</span></span>
    </span>
  );
}

/** What is left of an allowance's window, in words: with its name when it has one. */
const quotaLeft = (w: { label?: string; left: number }) =>
  w.label ? t("web-main.quota.left", { label: w.label, left: w.left }) : t("web-main.quota.leftAlone", { left: w.left });

/** An allowance's window (or the one an agent is short of): what is left written in it, filled as far as that.
 * `marked`: its mark before it (where there is more than one). */
export function QuotaChip({ window: w, marked = true, ...rest }: { window: { label?: string; mark: string; left: number; level: Level | string }; marked?: boolean } & ChipProps) {
  return <FillChip {...rest} fill={leftOf(w.left)} level={w.level} mark={marked ? w.mark : null} text={`${w.left}%`} label={quotaLeft(w)} />;
}

/** A machine's CPU, memory or disk: its name and what is left, filled as far as is used. `brief`: the figure alone,
 * small (a station's row). */
export function MeterChip({ meter: m, brief = false, ...rest }: { meter: Meter; brief?: boolean } & ChipProps) {
  const text = brief ? `${m.big}${m.unit === "%" ? "%" : m.unit.slice(0, 1)}` : m.remaining;
  return <FillChip small={brief} {...rest} fill={usedOf(m.left)} level={m.level} mark={m.short} text={text} label={`${m.label} ${m.remaining}`} />;
}

/** How much of something coming is in (0–100): in the accent, filled as far as that. */
export function ProgressChip({ percent, label, ...rest }: { percent: number; label: string } & ChipProps) {
  return <FillChip {...rest} fill={percent} level="progress" text={`${percent}%`} label={label} />;
}

/** A machine's CPU, memory and disk, each a MeterChip; what it is in the tip. `alerts`: only those running low. */
export function MeterChips({ meters, bare, alerts = false }: { meters: Meter[]; bare?: boolean; alerts?: boolean }) {
  return (
    <span className={css.quotaChips}>
      {meters.filter((m) => !alerts || m.level !== "ok").map((m) => (
        <Tip key={m.label} label={`${m.label} ${m.value}${m.note ? ` · ${m.note}` : ""}`}>
          <MeterChip meter={m} bare={bare} />
        </Tip>
      ))}
    </span>
  );
}

/** A small stack of people's avatars (as the core names them); names in the tooltip. */
export function PeopleStack({ people, max = 3 }: { people: { id: string; shown: PersonShown }[] | undefined; max?: number }) {
  if (!people?.length) return null;
  return (
    <Tip label={t("web-main.people.in", { names: people.map((p) => p.shown.display).join(t("web-main.list.separator")) })}><span className={css.peopleStack}>
      {people.slice(0, max).map((p) => p.shown.picture
        ? <img key={p.id} className={cloudCss.person} src={p.shown.picture} alt="" width={16} height={16} referrerPolicy="no-referrer" />
        : <span key={p.id} className={`${cloudCss.person} ${cloudCss.personLetter}`} aria-hidden="true">{([...p.shown.display][0] ?? "?").toUpperCase()}</span>)}
      {people.length > max && <span className={css.peopleMore}>+{people.length - max}</span>}
    </span></Tip>
  );
}

/** 外观: follow the system, or always light, or always dark (kept in this browser). */
export function AppearanceSetting() {
  const [appearance, setAppearance] = useAppearance();
  return (
    <Segmented label={t("web-main.appearance")} value={appearance} onChange={setAppearance}
      options={[{ value: "system", label: t("web-main.appearance.system") }, { value: "light", label: t("web-main.appearance.light") }, { value: "dark", label: t("web-main.appearance.dark") }]} />
  );
}
