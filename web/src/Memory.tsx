// The agents' memory on a station, in two layers, shown as it is (the agents write it): the global memory (what holds
// across projects, loaded at every session's start) and each project's memory, a skill whose description starts with
// 项目记忆： and says when it applies (its whole text is read when a task matches). The station's other skills are
// listed too.
import { useEffect, useState } from "react";
import { stationApi, useStationCall, type SkillFile, type StationMemory as Memory } from "./api.ts";
import { useTopic } from "./core/react.ts";
import type { StationView } from "./core/shapes.ts";
import { Prose } from "./Prose.tsx";
import { Section, SwitchRow } from "./ui.tsx";
import { useDoing } from "./doing.ts";
import { useAct } from "./toast.tsx";
import { ChevronDown, ChevronRight } from "./icons.tsx";
import * as css from "./Memory.css.ts";
import * as conversationCss from "./styles/conversation.css.ts";
import * as shellCss from "./styles/shell.css.ts";
import { t } from "./i18n.ts";

export type { SkillFile, StationMemory as Memory } from "./api.ts";

/** A skill as a row that opens to its text, rendered; whether it is shared with the workspace's other stations, or
 * whose it is (`station`: where it is, `changed`: the memory read again after a change). */
export function SkillRow({ skill, station, changed }: { skill: SkillFile; station?: string; changed?: () => void }) {
  const [open, setOpen] = useState(false);
  // What it is for and its text as people read it, the core's (a desktop core from before them: as written).
  const about = skill.about ?? skill.description;
  const share = skill.share;
  const stations = useTopic<StationView[]>(station ? { topic: "stations", scope: station.split("/")[0]! } : null).value ?? [];
  const nameOf = (id: string) => stations.find((x) => x.id === id)?.name ?? id.slice(0, 8);
  const call = useStationCall(station ?? "");
  const act = useAct();
  const sharing = useDoing("skill.share", { station, name: skill.name });
  return (
    <div className={css.memorySkill} data-open={open || undefined}>
      <button type="button" className={css.memorySkillRow} onClick={() => setOpen(!open)} aria-expanded={open}>
        {open ? <ChevronDown size={16} /> : <ChevronRight size={16} />}
        <span className={css.memorySkillText}>
          <b>{skill.name}{skill.builtin && <span className={css.memorySkillOwn}>{t("web-main.memory.builtin")}</span>}
            {share?.role === "user" && <span className={css.memorySkillOwn}>{t("web-main.memory.share.from", { station: nameOf(share.host) })}</span>}
            {share?.role === "host" && <span className={css.memorySkillOwn}>{t("web-main.memory.share.shared")}</span>}</b>
          <span>{about || t("web-main.memory.noWhen")}</span>
        </span>
      </button>
      {open && station && !skill.builtin && share?.role !== "user" && (
        <div className={css.memoryShare}>
          <SwitchRow title={t("web-main.memory.share.switch")} checked={share?.role === "host"} busy={sharing} disabled={sharing}
            onChange={(on) => act(stationApi(call).shareSkill(skill.name, on, null).then(() => changed?.()), t("web-main.memory.share.switch"))} />
          {(share?.conflicts?.length ?? 0) > 0 && <p className={css.memoryConflict}>{t("web-main.memory.share.conflict")}: {share!.conflicts!.join("、")}</p>}
        </div>
      )}
      {open && <div className={`${css.memoryDoc} ${conversationCss.markdown}`}><Prose>{(skill.body ?? skill.text) || t("web-main.memory.empty")}</Prose></div>}
    </div>
  );
}

/** What each part of the memory is, as both screens say it (the phone's page is ./mobile/Memory.tsx); read as shown. */
export const MEMORY_TEXT = {
  get global() { return t("web-main.memory.global.about"); },
  get projects() { return t("web-main.memory.projects.about"); },
  get none() { return t("web-main.memory.projects.none"); },
  get others() { return t("web-main.memory.others.about"); },
  failed: (error: string) => t("web-main.memory.failed", { error }),
};

/** A station's memory, read once (it changes as agents write it, not while it is looked at), or why it could not be. */
export function useMemory(station: string): { memory: Memory | null; error: string | null; reload: () => void } {
  const call = useStationCall(station);
  const [memory, setMemory] = useState<Memory | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [round, setRound] = useState(0);
  useEffect(() => { stationApi(call).memory<Memory>().then(setMemory, (e: Error) => setError(e.message)); }, [call, round]);
  return { memory, error, reload: () => setRound((n) => n + 1) };
}

/** A station's memory: global, projects', and its other skills. */
export function MemoryView({ station }: { station: string }) {
  const { memory, error, reload } = useMemory(station);
  if (error) return <p className={shellCss.muted}>{MEMORY_TEXT.failed(error)}</p>;
  if (!memory) return <p className={shellCss.muted}>{t("web-main.reading")}</p>;
  const projects = memory.skills.filter((s) => s.project);
  const others = memory.skills.filter((s) => !s.project);
  return (
    <>
      <Section title={t("web-main.memory.global")} description={MEMORY_TEXT.global}>
        <div className={`${css.memoryDoc} ${conversationCss.markdown}`}><Prose>{memory.global.text.trim() || t("web-main.memory.empty")}</Prose></div>
      </Section>
      <Section title={t("web-main.memory.projects")} description={MEMORY_TEXT.projects}>
        {projects.length === 0 && <p className={`${shellCss.muted} ${css.memoryNone}`}>{MEMORY_TEXT.none}</p>}
        {projects.map((s) => <SkillRow key={s.name} skill={s} station={station} changed={reload} />)}
      </Section>
      {others.length > 0 && (
        <Section title={t("web-main.memory.others")} description={MEMORY_TEXT.others}>
          {others.map((s) => <SkillRow key={s.name} skill={s} station={station} changed={reload} />)}
        </Section>
      )}
    </>
  );
}
