// Small pieces the station client and ember cloud share.
import { useAppearance } from "./theme.ts";
import type { Host, Level, PersonShown, Quota } from "./api.ts";
import { useOnlyMine } from "./station.tsx";
import { Segmented, Tip } from "./ui.tsx";
import { Check, Filter } from "./icons.tsx";
import { DropdownMenu } from "radix-ui";

/**
 * A filter: 全部 or only the viewer's (我参与的 for chats, 我创建的 for connects), from a menu. `compact`: a filter
 * button alone, marked while it filters; else the filter's name beside it.
 */
export function MineFilter({ label = "筛选", mine = "我创建的", compact }: { label?: string; mine?: string; compact?: boolean }) {
  const [onlyMine, setOnlyMine] = useOnlyMine();
  const item = (value: boolean, text: string) => (
    <DropdownMenu.Item className="menu-item chooser-item" onSelect={() => setOnlyMine(value)}>
      <span className="chooser-check">{onlyMine === value && <Check size={13} />}</span>{text}
    </DropdownMenu.Item>
  );
  return (
    <DropdownMenu.Root modal={false}>
      <DropdownMenu.Trigger className={compact ? "mine-filter-btn" : "mine-filter-btn mine-filter-wide"} title={`筛选${label}`} aria-label={`筛选${label}：${onlyMine ? mine : "全部"}`} data-on={onlyMine || undefined}>
        <Filter size={15} strokeWidth={1.8} />{!compact && <span>{onlyMine ? mine : "全部"}</span>}
      </DropdownMenu.Trigger>
      <DropdownMenu.Portal>
        <DropdownMenu.Content className="popover menu-list chooser-menu" align="end" sideOffset={6} collisionPadding={8}>
          {item(false, `全部${label}`)}
          {item(true, mine)}
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  );
}

/** "由 X 创建": the person as the core names them (你 for the viewer). */
export function CreatorText({ creator, verb = "创建" }: { creator: { via?: string | null; shown?: PersonShown } | null | undefined; verb?: string }) {
  if (!creator?.shown) return null;
  const where = creator.via === "slack" ? "（Slack）" : "";
  return <span className="creator">由 {creator.shown.display}{where} {verb}</span>;
}

/** Who a connect belongs to: avatar and name as the core names them. */
export function OwnerLabel({ owner }: { owner: { id: string; shown?: PersonShown } | null | undefined }) {
  if (!owner?.shown) return <span className="owner owner-none">未设置所属用户</span>;
  const { name, picture, mine } = owner.shown;
  return (
    <span className="owner" title={owner.id === "local" ? undefined : owner.id}>
      {picture
        ? <img className="person" src={picture} alt="" width={16} height={16} referrerPolicy="no-referrer" />
        : <span className="person person-letter" style={{ width: 16, height: 16, fontSize: 9 }} aria-hidden="true">{([...name][0] ?? "?").toUpperCase()}</span>}
      {mine ? `${name}（你）` : name}
    </span>
  );
}

/**
 * A profile's allowance, as the core puts its windows (shortest first, each marked): compact, a rounded box per window
 * with what is left written in it (its mark too when there is more than one), its edge drawn as far as is left.
 * `small`: where a line is lower than a row (the model control).
 */
export function QuotaBars({ quota, compact, small }: { quota: Quota | null | undefined; compact?: boolean; small?: boolean }) {
  if (!quota) return compact ? null : <p className="muted quota-note">还没查过额度。</p>;
  if (quota.state !== "ok" || quota.windows.length === 0) return compact ? null : <p className="muted quota-note">{quota.detail ?? "查不到额度。"}</p>;
  if (compact) {
    const lone = quota.windows.length === 1;
    return (
      <span className="quota-chips">
        {quota.windows.map((w) => (
          <Tip key={w.label} label={<>{w.label}剩余 {w.left}%{w.refills && <><br />{w.refills}</>}</>}>
            <span className="quota-chip" data-level={w.level} data-small={small || undefined} tabIndex={0} role="img" aria-label={`${w.label}剩余 ${w.left}%`}>
              <svg className="quota-chip-edge" aria-hidden="true">
                <rect className="quota-chip-track" pathLength={100} />
                {w.left > 0 && <rect className="quota-chip-left" pathLength={100} strokeDasharray={`${w.left} 100`} />}
              </svg>
              <span className="quota-chip-text">{!lone && <span className="quota-chip-mark">{w.mark}</span>}{w.left}%</span>
            </span>
          </Tip>
        ))}
      </span>
    );
  }
  // The profile's own page: each window a larger ring, what is left of it and when it refills under it.
  return (
    <div className="quota-dials">
      {quota.windows.map((w) => (
        <div key={w.label} className="quota-dial">
          <QuotaRing left={w.left} level={w.level} size={64} />
          <span className="quota-dial-label">{w.label}</span>
          <span className="quota-dial-reset">{w.refills ?? "\u00a0"}</span>
        </div>
      ))}
    </div>
  );
}

/** What is left of a window, as a ring: full when untouched, shorter as it goes, coloured by the core's `level`; the
 * number left inside (up to 99; a full ring says 100 by itself). Use eats it clockwise from the top. */
export function QuotaRing({ left, level, size = 26 }: { left: number; level: Level; size?: number }) {
  const used = 100 - left;
  const stroke = size > 40 ? 5 : 3;
  const c = size / 2;
  const r = c - stroke / 2 - 0.5;
  const around = 2 * Math.PI * r;
  return (
    <span className="quota-ring" data-level={level} data-size={size > 40 ? "large" : undefined} style={{ width: size, height: size }} role="img" aria-label={`剩余 ${left}%`}>
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} aria-hidden="true" style={{ strokeWidth: stroke }}>
        <circle className="quota-ring-track" cx={c} cy={c} r={r} />
        {left > 0 && <circle className="quota-ring-fill" cx={c} cy={c} r={r} strokeDasharray={`${(around * left) / 100} ${around}`} transform={`rotate(${-90 + used * 3.6} ${c} ${c})`} />}
      </svg>
      {left < 100 && <span className="quota-ring-number">{left}</span>}
    </span>
  );
}

/** A small stack of people's avatars (as the core names them); names in the tooltip. */
export function PeopleStack({ people, max = 3 }: { people: { id: string; shown: PersonShown }[] | undefined; max?: number }) {
  if (!people?.length) return null;
  return (
    <span className="people-stack" title={`参与：${people.map((p) => p.shown.display).join("、")}`}>
      {people.slice(0, max).map((p) => p.shown.picture
        ? <img key={p.id} className="person" src={p.shown.picture} alt="" width={16} height={16} referrerPolicy="no-referrer" />
        : <span key={p.id} className="person person-letter" aria-hidden="true">{([...p.shown.display][0] ?? "?").toUpperCase()}</span>)}
      {people.length > max && <span className="people-more">+{people.length - max}</span>}
    </span>
  );
}

function Meter({ meter }: { meter: Host["meters"][number] }) {
  return (
    <div className="quota-row device-row">
      <span className="quota-label">{meter.label}</span>
      <span className="quota-track"><span className="quota-fill" data-level={meter.level} style={{ width: `${meter.percent}%` }} /></span>
      <span className="device-value">{meter.value}</span>
      <span className="quota-reset">{meter.note ?? ""}</span>
    </div>
  );
}

/** The machine a station runs on: what it is, and how loaded (the core's words); `processes`: its agents', in a line. */
export function DeviceCard({ host, processes }: { host: Host | null | undefined; processes: string | undefined }) {
  if (!host) return <div className="device muted">正在读取设备信息…</div>;
  return (
    <div className="device">
      <div className="device-facts">{host.facts.map((f) => <span key={f}>{f}</span>)}</div>
      <div className="quota">{host.meters.map((m) => <Meter key={m.label} meter={m} />)}</div>
      <div className="device-facts muted">
        <span>{host.emberText}</span>
        {processes && <span>{processes}</span>}
      </div>
    </div>
  );
}

/** A percentage as a small ring, filled clockwise from the top; colour follows the same levels as the bars. */
export function Ring({ percent, level, size = 28, label, title }: { percent: number; level: Level; size?: number; label: string; title?: string }) {
  const p = percent;
  const r = (size - 4) / 2;
  const c = 2 * Math.PI * r;
  return (
    <span className="ring" title={title ?? `${label} ${p}%`}>
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} aria-hidden="true">
        <circle className="ring-track" cx={size / 2} cy={size / 2} r={r} />
        <circle className="ring-fill" data-level={level} cx={size / 2} cy={size / 2} r={r}
          strokeDasharray={`${(c * p) / 100} ${c}`} transform={`rotate(-90 ${size / 2} ${size / 2})`} />
        <text x="50%" y="50%" dominantBaseline="central" textAnchor="middle">{p}</text>
      </svg>
      <span className="ring-label">{label}</span>
    </span>
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
