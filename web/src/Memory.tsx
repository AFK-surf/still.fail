// The agents' memory on a station, in two layers, shown as it is (the agents write it): the global memory (what holds
// across projects, loaded at every session's start) and each project's memory, a skill whose description starts with
// 项目记忆： and says when it applies (its whole text is read when a task matches). The station's other skills are
// listed too. A page lists them (the global memory by its parts, a row for each skill), and each opens on a page of
// its own to be read: a skill with its other files, the global memory a part at a time.
import { useEffect, useState } from "react";
import { Link } from "react-router";
import { stationApi, useStationCall, type SkillFile, type StationMemory as Memory } from "./api.ts";
import type { MemorySection, StationView } from "./core/shapes.ts";
import { useTopic } from "./core/react.ts";
import { Prose } from "./Prose.tsx";
import { Section, SwitchRow } from "./ui.tsx";
import { useDoing } from "./doing.ts";
import { useAct } from "@stillfail/ui/toast.tsx";
import { ChevronDown, ChevronRight } from "@stillfail/ui/icons.tsx";
import * as css from "./Memory.css.ts";
import * as conversationCss from "./styles/conversation.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as shellCss from "./styles/shell.css.ts";
import { t } from "./i18n.ts";

export type { SkillFile, StationMemory as Memory } from "./api.ts";

/** A station's memory as both screens list it: the global memory's parts (all of it in one, from a core before
 * them), the projects', the team's other skills and the station's own. */
export function memoryParts(memory: Memory): { sections: MemorySection[]; projects: SkillFile[]; skills: SkillFile[]; builtin: SkillFile[] } {
  const text = memory.global.text.trim();
  const sections = memory.global.sections?.length ? memory.global.sections : text ? [{ title: t("web-main.memory.global"), text, note: "" }] : [];
  return {
    sections,
    projects: memory.skills.filter((s) => s.project),
    skills: memory.skills.filter((s) => !s.project && !s.builtin),
    builtin: memory.skills.filter((s) => !s.project && s.builtin),
  };
}

/** What a skill is for in a line, for its row (the core's; a core before it: when it applies, whole). */
export const skillBrief = (skill: SkillFile) => skill.brief ?? skill.about ?? skill.description;

/** A skill's pages as they are picked: its SKILL.md (总览) and each other file. */
export function skillPages(skill: SkillFile): { key: string; label: string; size?: string | undefined; text: string }[] {
  return [
    { key: "", label: t("web-main.memory.overview"), text: (skill.body ?? skill.text) || t("web-main.memory.empty") },
    ...(skill.files ?? []).map((f) => ({ key: f.name, label: f.label ?? f.name, size: f.size, text: f.text || t("web-main.memory.empty") })),
  ];
}

/** What kind of memory a skill is, as its page's subtitle says. */
export const skillKind = (skill: SkillFile) => t(skill.project ? "web-main.memory.projects" : skill.builtin ? "web-main.memory.builtin" : "web-main.memory.skill");

/** What each part of the memory is, as both screens say it (the phone's page is ./mobile/Memory.tsx). */
export const MEMORY_TEXT = {
  get global() { return t("web-main.memory.global.when"); },
  get projects() { return t("web-main.memory.projects.when"); },
  get none() { return t("web-main.memory.projects.none"); },
  failed: (error: string) => t("web-main.memory.failed", { error }),
};

/** The last memory read of each station, so a page opened from the list has it at once (it is read again). */
const kept = new Map<string, Memory>();

/** A station's memory, read as a page opens (it changes as agents write it, not while it is looked at), or why it
 * could not be. */
export function useMemory(station: string): { memory: Memory | null; error: string | null; reload: () => void } {
  const call = useStationCall(station);
  const [memory, setMemory] = useState<Memory | null>(() => kept.get(station) ?? null);
  const [error, setError] = useState<string | null>(null);
  const [round, setRound] = useState(0);
  useEffect(() => {
    stationApi(call).memory<Memory>().then((m) => { kept.set(station, m); setMemory(m); setError(null); }, (e: Error) => setError(e.message));
  }, [call, station, round]);
  return { memory, error, reload: () => setRound((n) => n + 1) };
}

/** Whose a skill is, after its name: the station's own, another station's, or shared from here. */
export function SkillTags({ skill, station, className }: { skill: SkillFile; station: string; className: string }) {
  const share = skill.share;
  const stations = useTopic<StationView[]>(share?.role === "user" ? { topic: "stations", scope: station.split("/")[0]! } : null).value ?? [];
  const nameOf = (id: string) => stations.find((x) => x.id === id)?.name ?? id.slice(0, 8);
  return (
    <>
      {share?.role === "user" && <span className={className}>{t("web-main.memory.share.from", { station: nameOf(share.host) })}</span>}
      {share?.role === "host" && <span className={className}>{t("web-main.memory.share.shared")}</span>}
    </>
  );
}

/** Whether a skill of this station's is shared with the workspace's other stations (none for the station's own or
 * another's copy), and the edits two stations made at once. */
export function SkillShare({ skill, station, changed }: { skill: SkillFile; station: string; changed: () => void }) {
  const call = useStationCall(station);
  const act = useAct();
  const sharing = useDoing("skill.share", { station, name: skill.name });
  const share = skill.share;
  if (skill.builtin || share?.role === "user") return null;
  return (
    <>
      <SwitchRow title={t("web-main.memory.share.switch")} checked={share?.role === "host"} busy={sharing} disabled={sharing}
        onChange={(on) => act(stationApi(call).shareSkill(skill.name, on, null).then(changed), t("web-main.memory.share.switch"))} />
      {(share?.conflicts?.length ?? 0) > 0 && <p className={css.memoryConflict}>{t("web-main.memory.share.conflicts", { names: share!.conflicts!.join(t("web-main.list.separator")) })}</p>}
    </>
  );
}

/** A row of the list that opens a page: its name (and whose), a line under it, how much is in it. */
function MemoryRow({ to, title, sub, value, tags }: { to: string; title: string; sub?: string | undefined; value?: string | undefined; tags?: React.ReactNode }) {
  return (
    <Link className={`${pagesCss.listRow} ${css.memoryRow}`} to={to}>
      <span className={pagesCss.listRowText}>
        <span className={css.memoryRowTitle}><span className={pagesCss.listRowTitle}>{title}</span>{tags}</span>
        {sub && <span className={css.memoryRowSub}>{sub}</span>}
      </span>
      {value && <span className={css.memoryRowValue}>{value}</span>}
      <ChevronRight size={14} className={css.memoryChevron} />
    </Link>
  );
}

/** A station's memory as a list (on the settings' memory page): the global memory by its parts, the projects', the
 * other skills, and the station's own folded in a row. `to` makes a page's address under this station's. */
export function MemoryView({ station, to }: { station: string; to: (page: string) => string }) {
  const { memory, error } = useMemory(station);
  const [builtinOpen, setBuiltinOpen] = useState(false);
  if (!memory) return <p className={shellCss.muted}>{error ? MEMORY_TEXT.failed(error) : t("web-main.reading")}</p>;
  const { sections, projects, skills, builtin } = memoryParts(memory);
  const skillRow = (s: SkillFile) => (
    <MemoryRow key={s.name} to={to(`skill/${encodeURIComponent(s.name)}`)} title={s.name} sub={skillBrief(s) || t("web-main.memory.noWhen")} value={s.size}
      tags={<SkillTags skill={s} station={station} className={css.memoryTag} />} />
  );
  return (
    <>
      <Section title={t("web-main.memory.global")} description={[MEMORY_TEXT.global, memory.global.size].filter(Boolean).join(" · ")}>
        {sections.length === 0 ? <p className={`${shellCss.muted} ${css.memoryNone}`}>{t("web-main.memory.empty")}</p>
          : sections.map((p, i) => <MemoryRow key={i} to={to(`global?at=${i}`)} title={p.title} value={p.note} />)}
      </Section>
      <Section title={t("web-main.memory.projects")} description={MEMORY_TEXT.projects}>
        {projects.length === 0 ? <p className={`${shellCss.muted} ${css.memoryNone}`}>{MEMORY_TEXT.none}</p> : projects.map(skillRow)}
      </Section>
      {skills.length + builtin.length > 0 && (
        <Section title={t("web-main.memory.others")}>
          {skills.map(skillRow)}
          {builtin.length > 0 && (
            <button type="button" className={`${pagesCss.listRow} ${css.memoryRow}`} onClick={() => setBuiltinOpen(!builtinOpen)} aria-expanded={builtinOpen}>
              <span className={pagesCss.listRowText}>
                <span className={pagesCss.listRowTitle}>{t("web-main.memory.builtin")}</span>
                {!builtinOpen && <span className={css.memoryRowSub}>{builtin.map((s) => s.name).join(t("web-main.list.separator"))}</span>}
              </span>
              <span className={css.memoryRowValue}>{t("web-main.memory.count", { n: builtin.length })}</span>
              {builtinOpen ? <ChevronDown size={14} className={css.memoryChevron} /> : <ChevronRight size={14} className={css.memoryChevron} />}
            </button>
          )}
          {builtinOpen && builtin.map(skillRow)}
        </Section>
      )}
    </>
  );
}

/** Pages to pick between, as a row of chips: a skill's files, the global memory's parts. */
export function DocChips({ items, picked, onPick, className, chip }: { items: { label: string; note?: string | undefined }[]; picked: number; onPick: (i: number) => void; className: string; chip: string }) {
  if (items.length < 2) return null;
  return (
    <div className={className} role="tablist">
      {items.map((x, i) => (
        <button key={i} type="button" role="tab" className={chip} aria-selected={i === picked} data-on={i === picked || undefined} onClick={() => onPick(i)}>
          {x.label}{x.note && <span>{x.note}</span>}
        </button>
      ))}
    </div>
  );
}

/** One of a station's memory pages on the wide screen (settings/memory/:station/global or /skill/:name, in
 * ./cloud/settings.tsx): a skill with when it is read, its sharing and its files, or the global memory a part at a time. */
export function MemoryDoc({ station, name, at, file, pick }: { station: string; name: string | null; at: number; file: string; pick: (key: "at" | "file", value: string | number) => void }) {
  const { memory, error, reload } = useMemory(station);
  if (!memory) return <p className={shellCss.muted}>{error ? MEMORY_TEXT.failed(error) : t("web-main.reading")}</p>;
  const doc = (text: string) => <div className={`${css.memoryDoc} ${conversationCss.markdown}`}><Prose>{text}</Prose></div>;
  if (name === null) {
    const { sections } = memoryParts(memory);
    const i = Math.min(Math.max(0, at), Math.max(0, sections.length - 1));
    return (
      <>
        <div className={css.memoryWhen}>{[MEMORY_TEXT.global, memory.global.size].filter(Boolean).join(" · ")}</div>
        <DocChips items={sections.map((p) => ({ label: p.title, note: p.note }))} picked={i} onPick={(n) => pick("at", n)} className={css.memoryChips} chip={css.memoryChip} />
        {doc(sections[i]?.text || t("web-main.memory.empty"))}
      </>
    );
  }
  const skill = memory.skills.find((s) => s.name === name);
  if (!skill) return <p className={shellCss.muted}>{t("web-main.memory.gone")}</p>;
  const pages = skillPages(skill);
  const i = Math.max(0, pages.findIndex((p) => p.key === file));
  return (
    <>
      <div className={`${pagesCss.card} ${css.memoryHead}`}>
        <div className={css.memoryWhen}><b>{skillKind(skill)} · {t("web-main.memory.when")}</b>{(skill.about ?? skill.description) || t("web-main.memory.noWhen")}</div>
        <SkillShare skill={skill} station={station} changed={reload} />
      </div>
      <DocChips items={pages.map((p) => ({ label: p.label, note: p.size }))} picked={i} onPick={(n) => pick("file", pages[n]!.key)} className={css.memoryChips} chip={css.memoryChip} />
      {doc(pages[i]!.text)}
    </>
  );
}
