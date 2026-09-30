// The agents' memory on a station on a narrow screen, as the Android app has it (apps/android/…/screens/Memory.kt), from
// the station's page: the wide screen's (../Memory.tsx: useMemory, SkillRow), its parts under section headers, the
// global memory on a card and the skills on another. Read only.
import { MEMORY_TEXT, SkillRow, useMemory } from "../Memory.tsx";
import { Prose } from "../Prose.tsx";
import { useStation } from "../station.tsx";
import { useApp } from "./app.tsx";
import { useStations } from "../api.ts";
import { Card, LargeTitle, ListCard, ListRow, Loading, NavBar, SectionHeader, TopBack } from "./parts.tsx";
import { GoRow } from "./Settings.tsx";
import * as settingsCss from "./styles/settings.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as listsCss from "./styles/lists.css.ts";
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

/**
 * The memory of every station, from settings (./Settings.tsx): a row for each, opening its memory (above); memory is
 * kept on each station and not shared between them.
 */
export function MemoriesScreen() {
  const app = useApp();
  const stations = useStations(app.entry.id).value;
  return (
    <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
      <TopBack label="设置" onBack={app.pop} />
      <LargeTitle small="" big="记忆" />
      <p className={settingsCss.mPageNote}>每台 station 上所有会话共用的记忆，由 agent 自己维护，各台 station 之间不同步。</p>
      {!stations ? <Loading text="正在读取 station…" /> : (
        <ListCard>
          {stations.map((s) => s.online
            ? <GoRow key={s.id} title={s.name} value="全局记忆 · 项目记忆" onClick={() => app.push(app.at(`/s/${s.id}/memory`))} />
            : <ListRow key={s.id}><span className={`${partsCss.mGrow} ${listsCss.mRowText}`}><span className={listsCss.mRowTitle}>{s.name}</span><span className={listsCss.mRowNote}>离线，读不到它的记忆</span></span></ListRow>)}
        </ListCard>
      )}
      <div style={{ height: 30 }} />
    </div>
  );
}
