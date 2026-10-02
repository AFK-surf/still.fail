// The agents' memory on a station, in two layers, shown as it is (the agents write it): the global memory (what holds
// across projects, loaded at every session's start) and each project's memory, a skill whose description starts with
// 项目记忆： and says when it applies (its whole text is read when a task matches). The station's other skills are
// listed too.
import { useEffect, useState } from "react";
import { stationApi, useStationCall, type SkillFile, type StationMemory as Memory } from "./api.ts";
import { Prose } from "./Prose.tsx";
import { Section } from "./ui.tsx";
import { ChevronDown, ChevronRight } from "./icons.tsx";
import * as css from "./Memory.css.ts";
import * as conversationCss from "./styles/conversation.css.ts";
import * as shellCss from "./styles/shell.css.ts";
import { t } from "./i18n.ts";

export type { SkillFile, StationMemory as Memory } from "./api.ts";

/** A skill as a row that opens to its text, rendered. */
export function SkillRow({ skill }: { skill: SkillFile }) {
  const [open, setOpen] = useState(false);
  // What it is for and its text as people read it, the core's (a desktop core from before them: as written).
  const about = skill.about ?? skill.description;
  return (
    <div className={css.memorySkill} data-open={open || undefined}>
      <button type="button" className={css.memorySkillRow} onClick={() => setOpen(!open)} aria-expanded={open}>
        {open ? <ChevronDown size={16} /> : <ChevronRight size={16} />}
        <span className={css.memorySkillText}>
          <b>{skill.name}{skill.builtin && <span className={css.memorySkillOwn}>{t("web-main.memory.builtin")}</span>}</b>
          <span>{about || t("web-main.memory.noWhen")}</span>
        </span>
      </button>
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
export function useMemory(station: string): { memory: Memory | null; error: string | null } {
  const call = useStationCall(station);
  const [memory, setMemory] = useState<Memory | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => { stationApi(call).memory<Memory>().then(setMemory, (e: Error) => setError(e.message)); }, [call]);
  return { memory, error };
}

/** A station's memory: global, projects', and its other skills. */
export function MemoryView({ station }: { station: string }) {
  const { memory, error } = useMemory(station);
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
        {projects.map((s) => <SkillRow key={s.name} skill={s} />)}
      </Section>
      {others.length > 0 && (
        <Section title={t("web-main.memory.others")} description={MEMORY_TEXT.others}>
          {others.map((s) => <SkillRow key={s.name} skill={s} />)}
        </Section>
      )}
    </>
  );
}
