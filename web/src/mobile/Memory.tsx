// The agents' memory on a station on a narrow screen, as the Android app has it (apps/android/…/screens/Memory.kt), from
// the station's page: the wide screen's (../Memory.tsx: useMemory, SkillRow), its parts under section headers, the
// global memory on a card and the skills on another. Read only.
import { MEMORY_TEXT, SkillRow, useMemory } from "../Memory.tsx";
import { Prose } from "../Prose.tsx";
import { useStation } from "../station.tsx";
import { useApp } from "./app.tsx";
import { Card, ListCard, Loading, NavBar, SectionHeader } from "./parts.tsx";
import * as css from "./Memory.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as rootCss from "./styles/root.css.ts";
import * as barsCss from "./styles/bars.css.ts";
import * as conversationCss from "../styles/conversation.css.ts";

export function MemoryScreen() {
  const app = useApp();
  const station = useStation();
  const { memory, error } = useMemory(station.address);
  const projects = memory?.skills.filter((k) => k.project) ?? [];
  const others = memory?.skills.filter((k) => !k.project) ?? [];
  return (
    <div className={pagesCss.mScreen}>
      <NavBar back={station.name} onBack={app.pop} title="记忆" sub={<span className={barsCss.mNavbarNote}>所有会话共用，由 agent 自己维护</span>} />
      {!memory ? <Loading text={error ? MEMORY_TEXT.failed(error) : "正在读取…"} /> : (
        <div className={pagesCss.mScroll} style={{ paddingTop: 4 }}>
          <SectionHeader title="全局记忆" start={24} />
          <p className={css.mMemoryNote}>{MEMORY_TEXT.global}</p>
          <Card><div className={`${rootCss.wide} ${conversationCss.markdown} ${css.mMemoryDoc}`}><Prose>{memory.global.text.trim() || "（空的）"}</Prose></div></Card>
          <SectionHeader title="项目记忆" start={24} />
          <p className={css.mMemoryNote}>{MEMORY_TEXT.projects}</p>
          {projects.length === 0 ? <p className={css.mMemoryNote}>{MEMORY_TEXT.none}</p>
            : <ListCard><div className={`${rootCss.wide} ${css.mMemorySkills}`}>{projects.map((k) => <SkillRow key={k.name} skill={k} />)}</div></ListCard>}
          {others.length > 0 && (
            <>
              <SectionHeader title="其他 skill" start={24} />
              <p className={css.mMemoryNote}>{MEMORY_TEXT.others}</p>
              <ListCard><div className={`${rootCss.wide} ${css.mMemorySkills}`}>{others.map((k) => <SkillRow key={k.name} skill={k} />)}</div></ListCard>
            </>
          )}
          <div style={{ height: 30 }} />
        </div>
      )}
    </div>
  );
}
