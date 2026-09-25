// Small pieces the station client and ember cloud share.
import { useEffect, useState } from "react";
import type { Creator, ProfileQuota } from "./api.ts";
import { readOnlyMine, useIsMine, usePerson, writeOnlyMine } from "./station.tsx";
import { Segmented } from "./ui.tsx";

export function useOnlyMine(): [boolean, (value: boolean) => void] {
  const [value, setValue] = useState(readOnlyMine);
  useEffect(() => {
    const update = () => setValue(readOnlyMine());
    window.addEventListener("ember-filter", update);
    return () => window.removeEventListener("ember-filter", update);
  }, []);
  return [value, writeOnlyMine];
}

/** 全部 / 我创建的 */
export function MineFilter({ label = "筛选" }: { label?: string }) {
  const [onlyMine, setOnlyMine] = useOnlyMine();
  return (
    <div className="mine-filter">
      <Segmented label={label} value={onlyMine ? "mine" : "all"} onChange={(v) => setOnlyMine(v === "mine")}
        options={[{ value: "all", label: "全部" }, { value: "mine", label: "我创建的" }]} />
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
    const top = [...quota.windows].sort((a, b) => b.usedPercent - a.usedPercent)[0]!;
    return (
      <span className="quota-compact" title={quota.windows.map((w) => `${w.label} ${w.usedPercent}%`).join(" · ")}>
        <span className="quota-track"><span className="quota-fill" data-level={level(top.usedPercent)} style={{ width: `${top.usedPercent}%` }} /></span>
        {top.label} {top.usedPercent}%
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
