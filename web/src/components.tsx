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
