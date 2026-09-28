// The agents' memory on a station, in two layers, shown as it is (the agents write it): the global memory (what holds
// across projects, loaded at every session's start) and each project's memory, a skill whose description starts with
// 项目记忆： and says when it applies (its whole text is read when a task matches). The station's other skills are
// listed too.
import { useEffect, useState } from "react";
import { useStationCall } from "./api.ts";
import { Prose } from "./Prose.tsx";
import { About, MobileBack, Section } from "./ui.tsx";
import { ChevronDown, ChevronRight } from "./icons.tsx";

interface SkillFile { name: string; description: string; project: boolean; builtin: boolean; text: string }
interface Memory { global: { path: string; text: string }; skills: SkillFile[] }

/** A SKILL.md without its frontmatter: what people read. */
function body(text: string): string {
  const m = /^---\n[\s\S]*?\n---\n?/.exec(text);
  return (m ? text.slice(m[0].length) : text).trim();
}

/** A skill as a row that opens to its text, rendered. */
function SkillRow({ skill }: { skill: SkillFile }) {
  const [open, setOpen] = useState(false);
  const about = skill.project ? skill.description.replace(/^项目记忆：/, "") : skill.description;
  return (
    <div className="memory-skill" data-open={open || undefined}>
      <button type="button" className="memory-skill-row" onClick={() => setOpen(!open)} aria-expanded={open}>
        {open ? <ChevronDown size={16} /> : <ChevronRight size={16} />}
        <span className="memory-skill-text">
          <b>{skill.name}{skill.builtin && <span className="memory-skill-own">station 自带</span>}</b>
          <span>{about || "（没写什么时候用）"}</span>
        </span>
      </button>
      {open && <div className="memory-doc markdown"><Prose>{body(skill.text) || "（空的）"}</Prose></div>}
    </div>
  );
}

/** A station's memory: global, projects', and its other skills. */
export function MemoryView({ station }: { station: string }) {
  const call = useStationCall(station);
  const [memory, setMemory] = useState<Memory | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => { call.request<Memory>("GET", "/memory").then(setMemory, (e: Error) => setError(e.message)); }, [call]);
  if (error) return <p className="muted">读不到这台 station 的记忆：{error}。更早的 station 还没有这一页，更新后就有。</p>;
  if (!memory) return <p className="muted">正在读取…</p>;
  const projects = memory.skills.filter((s) => s.project);
  const others = memory.skills.filter((s) => !s.project);
  return (
    <>
      <Section title="全局记忆" description="每个会话开始时都会读。只放跨项目都适用的：团队怎么协作、怎么回复。">
        <div className="memory-doc markdown"><Prose>{memory.global.text.trim() || "（空的）"}</Prose></div>
      </Section>
      <Section title="项目记忆" description="每个项目一份，是一个 skill：会话开始时只读「什么时候用」那句，做到相关的事才读全文。项目不一定是代码仓库。">
        {projects.length === 0 && <p className="muted memory-none">还没有项目记忆。agent 学到只跟某个项目有关的东西时，会自己建一个。</p>}
        {projects.map((s) => <SkillRow key={s.name} skill={s} />)}
      </Section>
      {others.length > 0 && (
        <Section title="其他 skill" description="团队共用的技能说明，agent 做到相关的事时读。">
          {others.map((s) => <SkillRow key={s.name} skill={s} />)}
        </Section>
      )}
    </>
  );
}

/** This station's memory, among its settings. */
export function MemoryPage() {
  return (
    <div className="page page-narrow">
      <MobileBack to="/settings" label="设置" />
      <header className="page-head"><div><h1>记忆<About>这台 station 上所有会话共用的记忆，Claude Code 和 Codex 都读，由 agent 自己维护。</About></h1></div></header>
      <MemoryView station="local" />
    </div>
  );
}
