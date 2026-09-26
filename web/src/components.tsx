// Small pieces the station client and ember cloud share.
import { useAppearance } from "./theme.ts";
import { useIsMine, type Creator, type HostInfo, type ProcessView, type ProfileQuota } from "./api.ts";
import { useOnlyMine, usePerson } from "./station.tsx";
import { Segmented } from "./ui.tsx";

/** 全部 / 我参与的 (chats) or 我创建的 (connects) */
export function MineFilter({ label = "筛选", mine = "我创建的" }: { label?: string; mine?: string }) {
  const [onlyMine, setOnlyMine] = useOnlyMine();
  return (
    <div className="mine-filter">
      <Segmented label={label} value={onlyMine ? "mine" : "all"} onChange={(v) => setOnlyMine(v === "mine")}
        options={[{ value: "all", label: "全部" }, { value: "mine", label: mine }]} />
    </div>
  );
}

/** "由 X 创建", with "你" for the viewer. */
export function CreatorText({ creator, verb = "创建" }: { creator: Pick<Creator, "id" | "name" | "email" | "via"> | null | undefined; verb?: string }) {
  const isMine = useIsMine();
  const person = usePerson();
  if (!creator) return null;
  // Names come from ember cloud's member list where the person is a member; the station only keeps emails.
  const who = isMine(creator) ? "你" : person(creator.email)?.name || creator.name || creator.email || creator.id;
  const where = creator.via === "slack" ? "（Slack）" : "";
  return <span className="creator">由 {who}{where} {verb}</span>;
}

/** Who a connect belongs to: avatar and name from ember cloud's members where known. */
export function OwnerLabel({ owner }: { owner: { id: string; name: string } | null | undefined }) {
  const isMine = useIsMine();
  const person = usePerson();
  if (!owner) return <span className="owner owner-none">未设置所属用户</span>;
  const member = person(owner.id);
  const name = owner.id === "local" ? "本机管理页" : member?.name || owner.name || owner.id;
  return (
    <span className="owner" title={owner.id === "local" ? undefined : owner.id}>
      {member?.picture
        ? <img className="person" src={member.picture} alt="" width={16} height={16} referrerPolicy="no-referrer" />
        : <span className="person person-letter" style={{ width: 16, height: 16, fontSize: 9 }} aria-hidden="true">{([...name][0] ?? "?").toUpperCase()}</span>}
      {isMine({ id: owner.id, email: owner.id }) ? `${name}（你）` : name}
    </span>
  );
}

/** When a quota window resets, in words: "3 小时后", "周日 08:00". */
function resetText(ms: number | null): string {
  if (ms === null) return "";
  const hours = (ms - Date.now()) / 3_600_000;
  if (hours <= 0) return "即将重置";
  if (hours < 24) return `${Math.max(1, Math.round(hours))} 小时后重置`;
  const d = new Date(ms);
  const day = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][d.getDay()];
  return `${hours < 24 * 7 ? day : `${d.getMonth() + 1}月${d.getDate()}日`} ${d.toLocaleTimeString("zh-CN", { hour: "2-digit", minute: "2-digit" })} 重置`;
}

const level = (p: number) => (p >= 90 ? "red" : p >= 70 ? "amber" : "ok");

/** A profile's allowance: one bar per window (compact: a single line of the fullest window). */
export function QuotaBars({ quota, compact }: { quota: ProfileQuota | null | undefined; compact?: boolean }) {
  if (!quota) return compact ? null : <p className="muted quota-note">还没查过额度。</p>;
  if (quota.state !== "ok" || quota.windows.length === 0) return compact ? null : <p className="muted quota-note">{quota.detail ?? "查不到额度。"}</p>;
  if (compact) {
    // Every window, shortest first, each a ring marked D (a day or less), W (a week), M (a month).
    const letter = (label: string) => (label.startsWith("每月") ? "M" : label.startsWith("每周") ? "W" : "D");
    const order = { D: 0, W: 1, M: 2 } as const;
    const windows = [...quota.windows].sort((a, b) => order[letter(a.label)] - order[letter(b.label)]);
    return (
      <span className="quota-rings">
        {windows.map((w) => (
          <span key={w.label} className="quota-ring-cell">
            <QuotaRing percent={w.usedPercent} title={`${w.label}剩余 ${100 - w.usedPercent}%${w.resetsAt ? `，${resetText(w.resetsAt)}` : ""}`} />
            <span className="quota-ring-letter">{letter(w.label)}</span>
          </span>
        ))}
      </span>
    );
  }
  return (
    <div className="quota">
      {quota.windows.map((w) => (
        <div key={w.label} className="quota-row">
          <span className="quota-label">{w.label}</span>
          <span className="quota-track"><span className="quota-fill" data-level={level(w.usedPercent)} style={{ width: `${w.usedPercent}%` }} /></span>
          <span className="quota-value">{w.usedPercent}%</span>
          <span className="quota-reset">{resetText(w.resetsAt)}</span>
        </div>
      ))}
    </div>
  );
}

/** What is left of the most used window, as a ring: full and green when untouched, shorter and redder as it goes; the
 * number left inside (up to 99; a full ring says 100 by itself). Use eats it clockwise from the top. */
function QuotaRing({ percent, title }: { percent: number; title: string }) {
  const used = Math.max(0, Math.min(100, Math.round(percent)));
  const left = 100 - used;
  const r = 10;
  const around = 2 * Math.PI * r;
  return (
    <span className="quota-ring" data-level={level(used)} title={title} role="img" aria-label={`剩余 ${left}%`}>
      <svg width="26" height="26" viewBox="0 0 26 26" aria-hidden="true">
        <circle className="quota-ring-track" cx="13" cy="13" r={r} />
        {left > 0 && <circle className="quota-ring-fill" cx="13" cy="13" r={r} strokeDasharray={`${(around * left) / 100} ${around}`} transform={`rotate(${-90 + used * 3.6} 13 13)`} />}
      </svg>
      {left < 100 && <span className="quota-ring-number">{left}</span>}
    </span>
  );
}

/** A small stack of people's avatars; names in the tooltip. */
export function PeopleStack({ people, max = 3 }: { people: Creator[] | undefined; max?: number }) {
  const person = usePerson();
  const isMine = useIsMine();
  if (!people?.length) return null;
  const name = (c: Creator) => (isMine(c) ? "你" : person(c.email)?.name || c.name || c.email || c.id);
  return (
    <span className="people-stack" title={`参与：${people.map(name).join("、")}`}>
      {people.slice(0, max).map((c) => {
        const picture = person(c.email)?.picture;
        return picture
          ? <img key={c.id} className="person" src={picture} alt="" width={16} height={16} referrerPolicy="no-referrer" />
          : <span key={c.id} className="person person-letter" aria-hidden="true">{([...name(c)][0] ?? "?").toUpperCase()}</span>;
      })}
      {people.length > max && <span className="people-more">+{people.length - max}</span>}
    </span>
  );
}

/** "参与：A、B、C" with avatars, for a session's header. */
export function Participants({ people }: { people: Creator[] | undefined }) {
  const person = usePerson();
  const isMine = useIsMine();
  if (!people?.length) return null;
  const name = (c: Creator) => (isMine(c) ? "你" : person(c.email)?.name || c.name || c.email || c.id);
  return (
    <span className="participants">
      <PeopleStack people={people} max={4} />
      <span className="participants-names">{people.slice(0, 4).map(name).join("、")}{people.length > 4 ? ` 等 ${people.length} 人` : ""}</span>
    </span>
  );
}

const gb = (bytes: number) => `${(bytes / 2 ** 30).toFixed(bytes >= 100 * 2 ** 30 ? 0 : 1)} GB`;

function uptime(sec: number): string {
  const days = Math.floor(sec / 86400);
  const hours = Math.floor((sec % 86400) / 3600);
  return days ? `${days} 天 ${hours} 小时` : `${hours} 小时`;
}

function Meter({ label, percent, value, note }: { label: string; percent: number; value: string; note?: string | undefined }) {
  const p = Math.max(0, Math.min(100, Math.round(percent)));
  return (
    <div className="quota-row device-row">
      <span className="quota-label">{label}</span>
      <span className="quota-track"><span className="quota-fill" data-level={p >= 90 ? "red" : p >= 75 ? "amber" : "ok"} style={{ width: `${p}%` }} /></span>
      <span className="device-value">{value}</span>
      <span className="quota-reset">{note ?? ""}</span>
    </div>
  );
}

/** The machine a station runs on: what it is, and how loaded. `processes` are the agents ember started. */
export function DeviceCard({ host, processes }: { host: HostInfo | undefined; processes?: ProcessView[] | undefined }) {
  if (!host) return <div className="device muted">正在读取设备信息…</div>;
  const mem = host.memory;
  const agentMb = (processes ?? []).reduce((sum, p) => sum + (p.rssMb ?? 0), 0);
  const used = host.disk.totalBytes - host.disk.freeBytes;
  return (
    <div className="device">
      <div className="device-facts">
        <span>{host.hostname}</span>
        <span>{host.os}</span>
        <span>{host.arch} · {host.cpus} 核</span>
        <span>已运行 {uptime(host.uptimeSec)}</span>
      </div>
      <div className="quota">
        <Meter label="CPU 负载" percent={host.load * 100} value={`${Math.round(host.load * 100)}%`} note={host.cpuModel} />
        <Meter label="内存" percent={(mem.usedBytes / mem.totalBytes) * 100} value={`${gb(mem.usedBytes)} / ${gb(mem.totalBytes)}`}
          note={mem.swapUsedBytes ? `swap ${gb(mem.swapUsedBytes)}` : undefined} />
        <Meter label="磁盘" percent={host.disk.totalBytes ? (used / host.disk.totalBytes) * 100 : 0} value={`剩 ${gb(host.disk.freeBytes)} / ${gb(host.disk.totalBytes)}`} />
      </div>
      <div className="device-facts muted">
        <span>ember {Math.round(host.emberRssBytes / 2 ** 20)} MB</span>
        <span>{processes?.length ? `${processes.length} 个 agent 进程 ${agentMb >= 1024 ? `${(agentMb / 1024).toFixed(1)} GB` : `${agentMb} MB`}` : "没有运行中的 agent 进程"}</span>
      </div>
    </div>
  );
}

/** A percentage as a small ring, filled clockwise from the top; colour follows the same levels as the bars. */
export function Ring({ percent, size = 28, label, title }: { percent: number; size?: number; label: string; title?: string }) {
  const p = Math.max(0, Math.min(100, Math.round(percent)));
  const r = (size - 4) / 2;
  const c = 2 * Math.PI * r;
  return (
    <span className="ring" title={title ?? `${label} ${p}%`}>
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} aria-hidden="true">
        <circle className="ring-track" cx={size / 2} cy={size / 2} r={r} />
        <circle className="ring-fill" data-level={level(p)} cx={size / 2} cy={size / 2} r={r}
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
