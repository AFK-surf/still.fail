// Small pieces the station client and ember cloud share.
import { useEffect, useState } from "react";
import type { Creator } from "./api.ts";
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
