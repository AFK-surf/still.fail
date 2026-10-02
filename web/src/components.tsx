// Small pieces the pages share.
import { useAppearance } from "./theme.ts";
import { useRef, type ComponentProps, type ReactNode } from "react";
import type { Level, PersonShown, Quota } from "./api.ts";
import type { Meter } from "./core/shapes.ts";
import { useChatFilter, useOnlyMine, type ChatFilter } from "./station.tsx";
import { Segmented, Tip } from "./ui.tsx";
import { Archive, Check, Filter } from "./icons.tsx";
import { useNavigate } from "react-router";
import { DropdownMenu } from "radix-ui";
import * as controlsCss from "./styles/controls.css.ts";
import * as chatCss from "./styles/chat.css.ts";
import * as css from "./components.css.ts";
import * as cloudCss from "./styles/cloud.css.ts";
import * as shellCss from "./styles/shell.css.ts";
import { t } from "./i18n.ts";

/**
 * A filter: 全部 or only the viewer's (我参与的 for chats, 我创建的 for connects), from a menu; for chats (`watching`)
 * also the watching ones (监控中). `compact`: a filter button alone, marked while it filters; else the filter's name
 * beside it. `archive`: the archive's page, the menu's last item under a line. Its words are the chats' with `watching`,
 * else the connects' (`label` and `mine`, which named them, are no longer read).
 */
export function MineFilter({ compact, archive, watching, decisions }: { label?: string; mine?: string; compact?: boolean; archive?: string | undefined; watching?: boolean; decisions?: { to: string; chats: string; active?: boolean } }) {
  const [onlyMine, setOnlyMine] = useOnlyMine();
  const [chatFilter, setChatFilter] = useChatFilter();
  // Chats: one of three (the core keeps 我参与的 and 监控中 apart); connects: all or mine.
  const filter: ChatFilter = watching ? chatFilter : onlyMine ? "mine" : "all";
  const setFilter = (value: ChatFilter) => watching ? setChatFilter(value) : setOnlyMine(value === "mine");
  const of = watching ? "chats" : "connects";
  const mine = t(`web-main.filter.${of}.mine`);
  const named = decisions?.active ? t("web-main.decisions.title") : filter === "mine" ? mine : filter === "watching" ? t("web-main.filter.watching") : t("web-main.filter.all");
  const navigate = useNavigate();
  // Gone to the archive, the focus is not brought back to the button (it would be ringed there, over the page left).
  const leaving = useRef(false);
  const item = (value: ChatFilter, text: string) => (
    <DropdownMenu.Item className={`${controlsCss.menuItem} ${chatCss.chooserItem}`} onSelect={() => { setFilter(value); if (decisions?.active) { leaving.current = true; navigate(decisions.chats); } }}>
      <span className={chatCss.chooserCheck}>{!decisions?.active && filter === value && <Check size={14} />}</span>{text}
    </DropdownMenu.Item>
  );
  return (
    <DropdownMenu.Root modal={false}>
      <Tip label={t(`web-main.filter.${of}`)}><DropdownMenu.Trigger className={compact ? css.mineFilterBtn : `${css.mineFilterBtn} ${css.mineFilterWide}`} aria-label={t(`web-main.filter.${of}.named`, { named })} data-on={decisions?.active || filter !== "all" || undefined}>
        <Filter size={16} strokeWidth={1.8} />{!compact && <span>{named}</span>}
      </DropdownMenu.Trigger></Tip>
      <DropdownMenu.Portal>
        <DropdownMenu.Content className={`${controlsCss.popover} ${controlsCss.menuList} ${chatCss.chooserMenu}`} align="end" sideOffset={6} collisionPadding={8}
          onCloseAutoFocus={(e) => { if (leaving.current) { leaving.current = false; e.preventDefault(); } }}>
          {item("all", t(`web-main.filter.${of}.all`))}
          {item("mine", mine)}
          {watching && item("watching", t("web-main.filter.watching"))}
          {decisions && <DropdownMenu.Item className={`${controlsCss.menuItem} ${chatCss.chooserItem}`} onSelect={() => { leaving.current = true; navigate(decisions.to); }}>
            <span className={chatCss.chooserCheck}>{decisions.active && <Check size={14} />}</span>{t("web-main.decisions.title")}
          </DropdownMenu.Item>}
          {archive && <>
            <DropdownMenu.Separator className={controlsCss.menuSep} />
            <DropdownMenu.Item className={`${controlsCss.menuItem} ${chatCss.chooserItem}`} onSelect={() => { leaving.current = true; navigate(archive); }}>
              <span className={chatCss.chooserCheck}><Archive size={14} /></span>{t("web-main.filter.archived")}
            </DropdownMenu.Item>
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
  return <span className={css.creator}>{t(`web-main.creator.${said}${creator.via === "slack" ? ".slack" : ""}`, { name: creator.shown.display })}</span>;
}

/** Who a connect belongs to: avatar and name as the core names them. */
export function OwnerLabel({ owner }: { owner: { id: string; shown?: PersonShown } | null | undefined }) {
  if (!owner?.shown) return <span className={`${css.owner} ${css.ownerNone}`}>{t("web-main.owner.none")}</span>;
  const { name, picture, mine } = owner.shown;
  return (
    <Tip label={owner.id === "local" ? undefined : owner.id}><span className={css.owner}>
      {picture
        ? <img className={cloudCss.person} src={picture} alt="" width={16} height={16} referrerPolicy="no-referrer" />
        : <span className={`${cloudCss.person} ${cloudCss.personLetter}`} style={{ width: 16, height: 16, fontSize: 9 }} aria-hidden="true">{([...name][0] ?? "?").toUpperCase()}</span>}
      {mine ? t("web-main.owner.you", { name }) : name}
    </span></Tip>
  );
}

/**
 * A profile's allowance, as the core puts its windows (shortest first, each marked): compact, a rounded box per window
 * with what is left written in it (its mark too when there is more than one), its edge drawn as far as is left.
 * `small`: where a line is lower than a row (the model control).
 */
export function QuotaBars({ quota, compact, small, bare }: { quota: Quota | null | undefined; compact?: boolean; small?: boolean; bare?: boolean }) {
  if (!quota) return compact ? null : <p className={`${shellCss.muted} ${css.quotaNote}`}>{t("web-main.quota.unchecked")}</p>;
  if (quota.state !== "ok" || quota.windows.length === 0) return compact ? null : <p className={`${shellCss.muted} ${css.quotaNote}`}>{quota.detail ?? t("web-main.quota.unknown")}</p>;
  if (compact) {
    const lone = quota.windows.length === 1;
    return (
      <span className={css.quotaChips}>
        {quota.windows.map((w) => (
          // Bare: inside a control, so not a stop of their own for the keyboard; the tip still shows on hover.
          <Tip key={w.label} label={<>{t("web-main.quota.left", { label: w.label, left: w.left })}{w.refills && <><br />{w.refills}</>}</>}>
            <EdgeChip fill={w.left} level={w.level} mark={lone ? null : w.mark} label={t("web-main.quota.left", { label: w.label, left: w.left })} small={small} bare={bare} />
          </Tip>
        ))}
      </span>
    );
  }
  // The profile's own page: each window's number large, ten cells lit as far as is left, its name and when it refills.
  return (
    <div className={css.quotaDials}>
      {quota.windows.map((w) => (
        <div key={w.label} className={css.quotaDial} data-level={w.level}>
          <span className={css.quotaDialNumber}>{w.left}<small>%</small></span>
          <span className={css.quotaDialCells} role="img" aria-label={t("web-main.quota.left", { label: w.label, left: w.left })}>
            {Array.from({ length: 10 }, (_, i) => <i key={i} data-on={i < Math.round(w.left / 10) || undefined} />)}
          </span>
          <span className={css.quotaDialLabel}>{w.label}</span>
          <span className={css.quotaDialReset}>{w.refills ?? "\u00a0"}</span>
        </div>
      ))}
    </div>
  );
}

/** A rounded box with a figure in it (its mark before it, when given) and its edge drawn as far as `fill` (0–100),
 * clockwise from the top left, in the colour of the core's `level`: an allowance's window, a machine's meter; or, as
 * level `progress`, how much of a download is in (in the accent, its edge moving smoothly to each new share). What else
 * it is given (a tip's trigger props and ref) goes on the box. */
export function EdgeChip({ fill, level, mark, label, text, small, bare, ...rest }: { fill: number; level: Level | string; mark?: ReactNode; label: string; text?: string | undefined; small?: boolean | undefined; bare?: boolean | undefined } & Omit<ComponentProps<"span">, "children">) {
  const p = Math.max(0, Math.min(100, fill));
  return (
    <span {...rest} className={css.quotaChip} data-level={level} data-small={small || undefined} tabIndex={bare ? undefined : 0} role="img" aria-label={label}>
      <svg className={css.quotaChipEdge} aria-hidden="true">
        <rect className={css.quotaChipTrack} pathLength={100} />
        {p > 0 && <rect className={css.quotaChipLeft} pathLength={100} strokeDasharray={`${p} 100`} />}
      </svg>
      <span className={css.quotaChipText}>{mark != null && <span className={css.quotaChipMark}>{mark}</span>}{text ?? `${fill}%`}</span>
    </span>
  );
}

/** A machine's CPU, memory and disk as the allowance's boxes are drawn: each its name and how full, its edge drawn as
 * far as that; what it is in the tip. */
export function MeterChips({ meters, bare, alerts = false }: { meters: Meter[]; bare?: boolean; alerts?: boolean }) {
  return (
    <span className={css.quotaChips}>
      {meters.filter((m) => !alerts || m.level !== "ok").map((m) => (
        <Tip key={m.label} label={`${m.label} ${m.value}${m.note ? ` · ${m.note}` : ""}`}>
          <EdgeChip fill={m.percent} level={m.level} mark={m.short} text={alerts ? m.remaining : undefined} label={`${m.label} ${m.percent}%${alerts && m.remaining ? ` · ${m.remaining}` : ""}`} bare={bare} />
        </Tip>
      ))}
    </span>
  );
}

/** What is left of a window, as a ring: full when untouched, shorter as it goes, coloured by the core's `level`; the
 * number left inside (up to 99; a full ring says 100 by itself). Use eats it clockwise from the top. */
export function QuotaRing({ left, level, size = 26 }: { left: number; level: Level; size?: number }) {
  const used = 100 - left;
  const stroke = 3;
  const c = size / 2;
  const r = c - stroke / 2 - 0.5;
  const around = 2 * Math.PI * r;
  return (
    <span className={css.quotaRing} data-level={level} style={{ width: size, height: size }} role="img" aria-label={t("web-main.quota.leftAlone", { left })}>
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} aria-hidden="true" style={{ strokeWidth: stroke }}>
        <circle className={css.quotaRingTrack} cx={c} cy={c} r={r} />
        {left > 0 && <circle className={css.quotaRingFill} cx={c} cy={c} r={r} strokeDasharray={`${(around * left) / 100} ${around}`} transform={`rotate(${-90 + used * 3.6} ${c} ${c})`} />}
      </svg>
      {left < 100 && <span className={css.quotaRingNumber}>{left}</span>}
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

/** A percentage as a small ring, filled clockwise from the top; colour follows the same levels as the bars. */
export function Ring({ percent, level, size = 28, label, title }: { percent: number; level: Level; size?: number; label: string; title?: string }) {
  const p = percent;
  const r = (size - 4) / 2;
  const c = 2 * Math.PI * r;
  return (
    <Tip label={title ?? `${label} ${p}%`}><span className={css.ring}>
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} aria-hidden="true">
        <circle className={css.ringTrack} cx={size / 2} cy={size / 2} r={r} />
        <circle className={css.ringFill} data-level={level} cx={size / 2} cy={size / 2} r={r}
          strokeDasharray={`${(c * p) / 100} ${c}`} transform={`rotate(-90 ${size / 2} ${size / 2})`} />
        <text x="50%" y="50%" dominantBaseline="central" textAnchor="middle">{p}</text>
      </svg>
      <span className="ring-label">{label}</span>
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
