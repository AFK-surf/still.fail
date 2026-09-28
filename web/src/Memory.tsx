// The agents' memory on a station, in two layers: the global memory (what holds across projects, loaded at every
// session's start) and each project's memory, a skill whose description starts with 项目记忆： and says when it applies
// (its whole text is read when a task matches). The station's other skills are listed too; its own are shown, not
// edited (it rewrites them at every start).
import { useEffect, useState } from "react";
import { useStationCall } from "./api.ts";
import { About, Button, Field, MobileBack, Section } from "./ui.tsx";
import { ChevronDown, ChevronRight, Plus } from "./icons.tsx";
import { useToast } from "./toast.tsx";

interface SkillFile { name: string; description: string; project: boolean; builtin: boolean; text: string }
interface Memory { global: { path: string; text: string }; skills: SkillFile[] }

/** Edits a text in place: saved when changed, with what it was until then. */
function TextEditor({ text, onSave, readOnly = false, rows = 12 }: { text: string; onSave?: (text: string) => Promise<void>; readOnly?: boolean; rows?: number }) {
  const [draft, setDraft] = useState(text);
  const [busy, setBusy] = useState(false);
  useEffect(() => setDraft(text), [text]);
  const changed = draft !== text;
  return (
    <div className="memory-editor">
      <textarea className="input memory-text" value={draft} rows={rows} readOnly={readOnly} spellCheck={false} onChange={(e) => setDraft(e.target.value)} />
      {!readOnly && onSave && (
        <div className="memory-actions">
          <Button variant="primary" disabled={!changed} busy={busy} onClick={() => { setBusy(true); void onSave(draft).finally(() => setBusy(false)); }}>保存</Button>
          {changed && <Button variant="ghost" onClick={() => setDraft(text)}>还原</Button>}
        </div>
      )}
    </div>
  );
}

/** A skill as a row that opens to its text. */
function SkillRow({ skill, onSave }: { skill: SkillFile; onSave?: (text: string) => Promise<void> }) {
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
      {open && <TextEditor text={skill.text} readOnly={skill.builtin} {...(onSave ? { onSave } : {})} rows={14} />}
    </div>
  );
}

/** A new project memory: its name and when it applies; the rest is written in it afterwards. */
function NewProject({ onMake, onCancel }: { onMake: (name: string, about: string) => Promise<void>; onCancel: () => void }) {
  const [name, setName] = useState("");
  const [about, setAbout] = useState("");
  const [busy, setBusy] = useState(false);
  return (
    <form className="memory-new" onSubmit={(e) => { e.preventDefault(); setBusy(true); void onMake(name.trim(), about.trim()).finally(() => setBusy(false)); }}>
      <Field label="名字" hint="字母、数字、中文、- 和 _，比如 ember、客户-某某、周报。" htmlFor="memory-new-name">
        <input id="memory-new-name" className="input" value={name} onChange={(e) => setName(e.target.value)} autoFocus />
      </Field>
      <Field label="什么时候用" hint="agent 靠这句话判断要不要读它：写清楚这是什么项目、做哪些事时用。" htmlFor="memory-new-about">
        <input id="memory-new-about" className="input" value={about} onChange={(e) => setAbout(e.target.value)} placeholder="开发、部署、排查 ember 时使用。" />
      </Field>
      <div className="memory-actions">
        <Button variant="primary" type="submit" disabled={!name.trim() || !about.trim()} busy={busy}>新建</Button>
        <Button variant="ghost" type="button" onClick={onCancel}>取消</Button>
      </div>
    </form>
  );
}

/** A station's memory: global, projects', and its other skills. */
export function MemoryEditor({ station }: { station: string }) {
  const call = useStationCall(station);
  const toast = useToast();
  const [memory, setMemory] = useState<Memory | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [adding, setAdding] = useState(false);
  const load = () => call.request<Memory>("GET", "/memory").then(setMemory, (e: Error) => setError(e.message));
  useEffect(() => { void load(); }, [call]); // eslint-disable-line react-hooks/exhaustive-deps
  if (error) return <p className="muted">读不到这台 station 的记忆：{error}。更早的 station 还没有这一页，更新后就有。</p>;
  if (!memory) return <p className="muted">正在读取…</p>;
  const saveSkill = (name: string) => async (text: string) => {
    try {
      await call.request("PUT", `/memory/skills/${encodeURIComponent(name)}`, { text });
      await load();
      toast(`「${name}」已保存`);
    } catch (e) {
      toast(`没能保存「${name}」：${(e as Error).message}`);
    }
  };
  const projects = memory.skills.filter((s) => s.project);
  const others = memory.skills.filter((s) => !s.project);
  return (
    <>
      <Section title="全局记忆" description="每个会话开始时都会读。只放跨项目都适用的：团队怎么协作、怎么回复。某个项目专属的写进它的项目记忆。">
        <TextEditor text={memory.global.text} onSave={async (text) => {
          try {
            await call.request("PUT", "/memory/global", { text });
            await load();
            toast("全局记忆已保存");
          } catch (e) {
            toast(`没能保存全局记忆：${(e as Error).message}`);
          }
        }} />
      </Section>
      <Section title="项目记忆" description="每个项目一份，是一个 skill：会话开始时只读「什么时候用」那句，做到相关的事才读全文。项目不一定是代码仓库。"
        actions={!adding && <Button icon={Plus} onClick={() => setAdding(true)}>新建项目记忆</Button>}>
        {adding && <NewProject onCancel={() => setAdding(false)} onMake={async (name, about) => {
          try {
            await call.request("POST", "/memory/skills", { name, about });
            setAdding(false);
            await load();
            toast(`已新建「${name}」`);
          } catch (e) {
            toast(`没能新建：${(e as Error).message}`);
          }
        }} />}
        {projects.length === 0 && !adding && <p className="muted memory-none">还没有项目记忆。agent 学到只跟某个项目有关的东西时，会自己建一个。</p>}
        {projects.map((s) => <SkillRow key={s.name} skill={s} onSave={saveSkill(s.name)} />)}
      </Section>
      {others.length > 0 && (
        <Section title="其他 skill" description="团队共用的技能说明；station 自带的每次启动都会重写，这里只能看。">
          {others.map((s) => <SkillRow key={s.name} skill={s} {...(s.builtin ? {} : { onSave: saveSkill(s.name) })} />)}
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
      <header className="page-head"><div><h1>记忆<About>这台 station 上所有会话共用的记忆，Claude Code 和 Codex 都读。</About></h1></div></header>
      <MemoryEditor station="local" />
    </div>
  );
}
