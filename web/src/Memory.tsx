// The agents' memory on a station, in two layers, shown as it is (the agents write it): the global memory (what holds
// across projects, loaded at every session's start) and each project's memory, a skill whose description starts with
// 项目记忆： and says when it applies (its whole text is read when a task matches). The station's other skills are
// listed too. A page lists them (the global memory by its parts, a row for each skill), and each opens on a page of
// its own to be read: a skill with its other files, the global memory a part at a time.
import { useState } from "react";
import { Link } from "react-router";
import { stationApi, useStationCall, type SkillFile, type StationMemory as Memory } from "./api.ts";
import type { MemorySection, StationView } from "./core/shapes.ts";
import { useTopic } from "./core/react.ts";
import { Prose } from "./Prose.tsx";
import { Section, SwitchRow, Waiting } from "./ui.tsx";
import { useDoing } from "./doing.ts";
import { useAct } from "@stillfail/ui/toast.tsx";
import { ChevronDown, ChevronRight } from "@stillfail/ui/icons.tsx";
import * as css from "./Memory.css.ts";
import * as conversationCss from "./styles/conversation.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as shellCss from "./styles/shell.css.ts";
import { t } from "./i18n.ts";
import { sampleMemory } from "./samples.ts";

export type { SkillFile, StationMemory as Memory } from "./api.ts";

/** A station's memory as both screens list it: the global memory's parts (the core's), the projects', the team's
 * other skills and the station's own (each skill's `group`, the core's). */
export function memoryParts(memory: Memory): { sections: MemorySection[]; projects: SkillFile[]; skills: SkillFile[]; builtin: SkillFile[] } {
  const sections = memory.global.sections ?? [];
  return {
    sections,
    projects: memory.skills.filter((s) => s.group === "project"),
    skills: memory.skills.filter((s) => s.group === "skill"),
    builtin: memory.skills.filter((s) => s.group === "builtin"),
  };
}

/** What each part of the memory is, as both screens say it (the phone's page is ./mobile/Memory.tsx). */
export const MEMORY_TEXT = {
  get global() { return t("web-main.memory.global.when"); },
  get projects() { return t("web-main.memory.projects.when"); },
  get none() { return t("web-main.memory.projects.none"); },
  failed: (error: string) => t("web-main.memory.failed", { error }),
};

/** A station's memory as the core holds it (the `memory` topic: read each time a page shows it, what was read last
 * shown meanwhile, the app opened again too), or why it could not be read while none is held. */
export function useMemory(station: string): { memory: Memory | null; error: string | null } {
  const topic = useTopic<Memory>({ topic: "memory", station });
  return { memory: topic.value ?? null, error: topic.value === undefined ? (topic.error?.message ?? null) : null };
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
 * another's copy; the core reads the memory again once it changes), and the edits two stations made at once. */
export function SkillShare({ skill, station }: { skill: SkillFile; station: string }) {
  const call = useStationCall(station);
  const act = useAct();
  const sharing = useDoing("skill.share", { station, name: skill.name });
  const share = skill.share;
  const host = share?.role === "host";
  const stations = useTopic<StationView[]>(host ? { topic: "stations", scope: station.split("/")[0]! } : null).value ?? [];
  const nameOf = (id: string) => stations.find((x) => x.id === id)?.name ?? id.slice(0, 8);
  if (skill.builtin || share?.role === "user") return null;
  const users = host ? (share?.users ?? []).map(nameOf) : [];
  return (
    <>
      <SwitchRow title={t("web-main.memory.share.switch")} checked={host} busy={sharing} disabled={sharing}
        onChange={(on) => act(stationApi(call).shareSkill(skill.name, on, null), t("web-main.memory.share.switch"))} />
      {users.length > 0 && <p className={css.memoryUsers}>{t("web-main.memory.share.users", { stations: users.join(t("web-main.list.separator")) })}</p>}
      {host && (share?.missing ?? []).map((m) => <p key={m.station} className={css.memoryConflict}>{t("web-main.memory.share.missing", { station: nameOf(m.station), why: m.whyText })}</p>)}
      {host && share?.unreadText && <p className={css.memoryConflict}>{share.unreadText}</p>}
      {(share?.conflicts?.length ?? 0) > 0 && <p className={css.memoryConflict}>{t("web-main.memory.share.conflicts", { names: share!.conflicts!.join(t("web-main.list.separator")) })}</p>}
    </>
  );
}

/** A row of the list that opens a page: its name (and whose), a line under it, how much is in it. */
function MemoryRow({ to, title, sub, value, tags }: { to: string; title: string; sub?: string | undefined; value?: string | undefined; tags?: React.ReactNode }) {
  return (
    <li>
      <Link className={`${pagesCss.listRow} ${css.memoryRow}`} to={to}>
        <span className={pagesCss.listRowText}>
          <span className={css.memoryRowTitle}><span className={pagesCss.listRowTitle}>{title}</span>{tags}</span>
          {sub && <span className={css.memoryRowSub}>{sub}</span>}
        </span>
        {value && <span className={css.memoryRowValue}>{value}</span>}
        <ChevronRight size={14} className={css.memoryChevron} />
      </Link>
    </li>
  );
}

/** A station's memory as lists (on its settings' page), each a card: the global memory by its parts, the projects', the
 * other skills, and the station's own folded in a row. `to` makes a page's address under this station's. */
export function MemoryView({ station, to }: { station: string; to: (page: string) => string }) {
  const { memory, error } = useMemory(station);
  if (!memory) return <Waiting error={error ? MEMORY_TEXT.failed(error) : null} sample={<MemoryLists station={station} memory={SAMPLE_MEMORY} to={to} />} />;
  return <MemoryLists station={station} memory={memory} to={to} />;
}

/** A station's memory made up, for what its pages show while it is read (in their bones). */
export const SAMPLE_MEMORY = sampleMemory();

/** A station's `memory` as MemoryView lists it. */
export function MemoryLists({ station, memory, to }: { station: string; memory: Memory; to: (page: string) => string }) {
  const [builtinOpen, setBuiltinOpen] = useState(false);
  const { sections, projects, skills, builtin } = memoryParts(memory);
  const skillRow = (s: SkillFile) => (
    <MemoryRow key={s.name} to={to(`skill/${encodeURIComponent(s.name)}`)} title={s.name} sub={s.line ?? ""} value={s.size}
      tags={<SkillTags skill={s} station={station} className={css.memoryTag} />} />
  );
  return (
    <>
      <Section title={t("web-main.memory.global")} description={[MEMORY_TEXT.global, memory.global.size].filter(Boolean).join(" · ")}>
        {sections.length === 0 ? <p className={`${shellCss.muted} ${css.memoryNone}`}>{t("web-main.memory.empty")}</p>
          : <ul className={pagesCss.list}>{sections.map((p, i) => <MemoryRow key={i} to={to(`global?at=${i}`)} title={p.title} value={p.note} />)}</ul>}
      </Section>
      <Section title={t("web-main.memory.projects")} description={MEMORY_TEXT.projects}>
        {projects.length === 0 ? <p className={`${shellCss.muted} ${css.memoryNone}`}>{MEMORY_TEXT.none}</p> : <ul className={pagesCss.list}>{projects.map(skillRow)}</ul>}
      </Section>
      {skills.length + builtin.length > 0 && (
        <Section title={t("web-main.memory.others")}>
          <ul className={pagesCss.list}>
            {skills.map(skillRow)}
            {builtin.length > 0 && (
              <li>
                <button type="button" className={`${pagesCss.listRow} ${css.memoryRow}`} onClick={() => setBuiltinOpen(!builtinOpen)} aria-expanded={builtinOpen}>
                  <span className={pagesCss.listRowText}>
                    <span className={pagesCss.listRowTitle}>{t("web-main.memory.builtin")}</span>
                    {!builtinOpen && <span className={css.memoryRowSub}>{builtin.map((s) => s.name).join(t("web-main.list.separator"))}</span>}
                  </span>
                  <span className={css.memoryRowValue}>{t("web-main.memory.count", { n: builtin.length })}</span>
                  {builtinOpen ? <ChevronDown size={14} className={css.memoryChevron} /> : <ChevronRight size={14} className={css.memoryChevron} />}
                </button>
              </li>
            )}
            {builtinOpen && builtin.map(skillRow)}
          </ul>
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
  const { memory, error } = useMemory(station);
  if (!memory) return <Waiting error={error ? MEMORY_TEXT.failed(error) : null} sample={<MemoryDocSample station={station} skill={name !== null} />} />;
  return <MemoryPage station={station} memory={memory} name={name} at={at} file={file} pick={pick} />;
}

/** One of MemoryDoc's pages made up, for what it shows while the memory is read (in its bones): a skill's, or the global memory's. */
export function MemoryDocSample({ station, skill }: { station: string; skill: boolean }) {
  return <MemoryPage station={station} memory={SAMPLE_MEMORY} name={skill ? SAMPLE_MEMORY.skills[0]!.name : null} at={0} file="" pick={() => undefined} />;
}

/** A page of a station's `memory`, as MemoryDoc shows it. */
function MemoryPage({ station, memory, name, at, file, pick }: { station: string; memory: Memory; name: string | null; at: number; file: string; pick: (key: "at" | "file", value: string | number) => void }) {
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
  const pages = skill.pages ?? [];
  const i = Math.max(0, pages.findIndex((p) => p.key === file));
  return (
    <>
      <div className={`${pagesCss.card} ${css.memoryHead}`}>
        <div className={css.memoryWhen}><b>{skill.kindText} · {t("web-main.memory.when")}</b>{skill.whenText}</div>
        <SkillShare skill={skill} station={station} />
      </div>
      <DocChips items={pages.map((p) => ({ label: p.label, note: p.size }))} picked={i} onPick={(n) => pick("file", pages[n]!.key)} className={css.memoryChips} chip={css.memoryChip} />
      {doc(pages[i]!.text)}
    </>
  );
}
