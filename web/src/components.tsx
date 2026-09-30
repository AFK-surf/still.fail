// Small pieces the pages share.
import { useAppearance } from "./theme.ts";
import { useRowPicture } from "./rowLead.ts";
import { useRef, type ComponentProps, type ReactNode } from "react";
import type { Level, PersonShown, Quota } from "./api.ts";
import type { Meter } from "./core/shapes.ts";
import { useOnlyMine } from "./station.tsx";
import { Segmented, Tip } from "./ui.tsx";
import { Archive, Check, Filter } from "./icons.tsx";
import { useNavigate } from "react-router";
import { DropdownMenu } from "radix-ui";
import * as controlsCss from "./styles/controls.css.ts";
import * as chatCss from "./styles/chat.css.ts";
import * as css from "./components.css.ts";
import * as cloudCss from "./styles/cloud.css.ts";
import * as shellCss from "./styles/shell.css.ts";

/**
 * A filter: 全部 or only the viewer's (我参与的 for chats, 我创建的 for connects), from a menu. `compact`: a filter
 * button alone, marked while it filters; else the filter's name beside it. `archive`: the archive's page, the menu's
 * last item under a line.
 */
export function MineFilter({ label = "筛选", mine = "我创建的", compact, archive }: { label?: string; mine?: string; compact?: boolean; archive?: string | undefined }) {
  const [onlyMine, setOnlyMine] = useOnlyMine();
  const navigate = useNavigate();
  // Gone to the archive, the focus is not brought back to the button (it would be ringed there, over the page left).
  const leaving = useRef(false);
  const item = (value: boolean, text: string) => (
    <DropdownMenu.Item className={`${controlsCss.menuItem} ${chatCss.chooserItem}`} onSelect={() => setOnlyMine(value)}>
      <span className={chatCss.chooserCheck}>{onlyMine === value && <Check size={14} />}</span>{text}
    </DropdownMenu.Item>
  );
  return (
    <DropdownMenu.Root modal={false}>
      <Tip label={`筛选${label}`}><DropdownMenu.Trigger className={compact ? css.mineFilterBtn : `${css.mineFilterBtn} ${css.mineFilterWide}`} aria-label={`筛选${label}：${onlyMine ? mine : "全部"}`} data-on={onlyMine || undefined}>
        <Filter size={16} strokeWidth={1.8} />{!compact && <span>{onlyMine ? mine : "全部"}</span>}
      </DropdownMenu.Trigger></Tip>
      <DropdownMenu.Portal>
        <DropdownMenu.Content className={`${controlsCss.popover} ${controlsCss.menuList} ${chatCss.chooserMenu}`} align="end" sideOffset={6} collisionPadding={8}
          onCloseAutoFocus={(e) => { if (leaving.current) { leaving.current = false; e.preventDefault(); } }}>
          {item(false, `全部${label}`)}
          {item(true, mine)}
          {archive && <>
            <DropdownMenu.Separator className={controlsCss.menuSep} />
            <DropdownMenu.Item className={`${controlsCss.menuItem} ${chatCss.chooserItem}`} onSelect={() => { leaving.current = true; navigate(archive); }}>
              <span className={chatCss.chooserCheck}><Archive size={14} /></span>已归档
            </DropdownMenu.Item>
          </>}
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  );
}

/** "由 X 创建": the person as the core names them (你 for the viewer). */
export function CreatorText({ creator, verb = "创建" }: { creator: { via?: string | null; shown?: PersonShown } | null | undefined; verb?: string }) {
  if (!creator?.shown) return null;
  const where = creator.via === "slack" ? "（Slack）" : "";
  return <span className={css.creator}>由 {creator.shown.display}{where} {verb}</span>;
}

/** Who a connect belongs to: avatar and name as the core names them. */
export function OwnerLabel({ owner }: { owner: { id: string; shown?: PersonShown } | null | undefined }) {
  if (!owner?.shown) return <span className={`${css.owner} ${css.ownerNone}`}>未设置所属用户</span>;
  const { name, picture, mine } = owner.shown;
  return (
    <Tip label={owner.id === "local" ? undefined : owner.id}><span className={css.owner}>
      {picture
        ? <img className={cloudCss.person} src={picture} alt="" width={16} height={16} referrerPolicy="no-referrer" />
        : <span className={`${cloudCss.person} ${cloudCss.personLetter}`} style={{ width: 16, height: 16, fontSize: 9 }} aria-hidden="true">{([...name][0] ?? "?").toUpperCase()}</span>}
      {mine ? `${name}（你）` : name}
    </span></Tip>
  );
}

/**
 * A profile's allowance, as the core puts its windows (shortest first, each marked): compact, a rounded box per window
 * with what is left written in it (its mark too when there is more than one), its edge drawn as far as is left.
 * `small`: where a line is lower than a row (the model control).
 */
export function QuotaBars({ quota, compact, small, bare }: { quota: Quota | null | undefined; compact?: boolean; small?: boolean; bare?: boolean }) {
  if (!quota) return compact ? null : <p className={`${shellCss.muted} ${css.quotaNote}`}>还没查过额度。</p>;
  if (quota.state !== "ok" || quota.windows.length === 0) return compact ? null : <p className={`${shellCss.muted} ${css.quotaNote}`}>{quota.detail ?? "查不到额度。"}</p>;
  if (compact) {
    const lone = quota.windows.length === 1;
    return (
      <span className={css.quotaChips}>
        {quota.windows.map((w) => (
          // Bare: inside a control, so not a stop of their own for the keyboard; the tip still shows on hover.
          <Tip key={w.label} label={<>{w.label}剩余 {w.left}%{w.refills && <><br />{w.refills}</>}</>}>
            <EdgeChip fill={w.left} level={w.level} mark={lone ? null : w.mark} label={`${w.label}剩余 ${w.left}%`} small={small} bare={bare} />
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
          <span className={css.quotaDialCells} role="img" aria-label={`${w.label}剩余 ${w.left}%`}>
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
 * clockwise from the top left, in the colour of the core's `level`: an allowance's window, a machine's meter. What else
 * it is given (a tip's trigger props and ref) goes on the box. */
function EdgeChip({ fill, level, mark, label, small, bare, ...rest }: { fill: number; level: Level | string; mark?: ReactNode; label: string; small?: boolean | undefined; bare?: boolean | undefined } & Omit<ComponentProps<"span">, "children">) {
  const p = Math.max(0, Math.min(100, fill));
  return (
    <span {...rest} className={css.quotaChip} data-level={level} data-small={small || undefined} tabIndex={bare ? undefined : 0} role="img" aria-label={label}>
      <svg className={css.quotaChipEdge} aria-hidden="true">
        <rect className={css.quotaChipTrack} pathLength={100} />
        {p > 0 && <rect className={css.quotaChipLeft} pathLength={100} strokeDasharray={`${p} 100`} />}
      </svg>
      <span className={css.quotaChipText}>{mark != null && <span className={css.quotaChipMark}>{mark}</span>}{fill}%</span>
    </span>
  );
}

/** A machine's CPU, memory and disk as the allowance's boxes are drawn: each its name and how full, its edge drawn as
 * far as that; what it is in the tip. */
export function MeterChips({ meters, bare }: { meters: Meter[]; bare?: boolean }) {
  return (
    <span className={css.quotaChips}>
      {meters.map((m) => (
        <Tip key={m.label} label={`${m.label} ${m.value}${m.note ? ` · ${m.note}` : ""}`}>
          <EdgeChip fill={m.percent} level={m.level} mark={m.short} label={`${m.label} ${m.percent}%`} bare={bare} />
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
    <span className={css.quotaRing} data-level={level} style={{ width: size, height: size }} role="img" aria-label={`剩余 ${left}%`}>
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
    <Tip label={`参与：${people.map((p) => p.shown.display).join("、")}`}><span className={css.peopleStack}>
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
    <Segmented label="外观" value={appearance} onChange={setAppearance}
      options={[{ value: "system", label: "跟随系统" }, { value: "light", label: "浅色" }, { value: "dark", label: "深色" }]} />
  );
}

/** 侧栏头像: whose pictures lead a chat's row (rowLead.ts), kept in this browser. */
export function RowPictureSetting() {
  const [value, setValue] = useRowPicture();
  return (
    <Segmented label="侧栏头像" value={value} onChange={setValue}
      options={[{ value: "auto", label: "自动" }, { value: "agents", label: "Agent 为主" }, { value: "people", label: "人为主" }]} />
  );
}
