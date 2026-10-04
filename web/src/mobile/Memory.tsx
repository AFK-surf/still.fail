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
import { t } from "../i18n.ts";

export function MemoryScreen() {
  const app = useApp();
  const station = useStation();
  const { memory, error, reload } = useMemory(station.address);
  const projects = memory?.skills.filter((k) => k.project) ?? [];
  const others = memory?.skills.filter((k) => !k.project) ?? [];
  return (
    <div className={pagesCss.mScreen}>
      <NavBar back={station.name} onBack={app.pop} title={t("web-mobile.settings.memory")} sub={<span className={barsCss.mNavbarNote}>{t("web-mobile.memory.sub")}</span>} />
      {!memory ? <Loading text={error ? MEMORY_TEXT.failed(error) : t("web-mobile.reading")} /> : (
        <div className={pagesCss.mScroll} style={{ paddingTop: 4 }}>
          <SectionHeader title={t("web-mobile.memory.global")} start={24} />
          <p className={css.mMemoryNote}>{MEMORY_TEXT.global}</p>
          <Card><div className={`${rootCss.wide} ${conversationCss.markdown} ${css.mMemoryDoc}`}><Prose>{memory.global.text.trim() || t("web-mobile.memory.empty")}</Prose></div></Card>
          <SectionHeader title={t("web-mobile.memory.projects")} start={24} />
          <p className={css.mMemoryNote}>{MEMORY_TEXT.projects}</p>
          {projects.length === 0 ? <p className={css.mMemoryNote}>{MEMORY_TEXT.none}</p>
            : <ListCard><div className={`${rootCss.wide} ${css.mMemorySkills}`}>{projects.map((k) => <SkillRow key={k.name} skill={k} station={station.address} changed={reload} />)}</div></ListCard>}
          {others.length > 0 && (
            <>
              <SectionHeader title={t("web-mobile.memory.others")} start={24} />
              <p className={css.mMemoryNote}>{MEMORY_TEXT.others}</p>
              <ListCard><div className={`${rootCss.wide} ${css.mMemorySkills}`}>{others.map((k) => <SkillRow key={k.name} skill={k} station={station.address} changed={reload} />)}</div></ListCard>
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
      <TopBack label={t("web-mobile.settings.title")} onBack={app.pop} />
      <LargeTitle small="" big={t("web-mobile.settings.memory")} />
      <p className={settingsCss.mPageNote}>{t("web-mobile.memory.note")}</p>
      {!stations ? <Loading text={t("web-mobile.memory.readingStations")} /> : (
        <ListCard>
          {stations.map((s) => s.online
            ? <GoRow key={s.id} title={s.name} value={t("web-mobile.memory.both")} onClick={() => app.push(app.at(`/s/${s.id}/memory`))} />
            : <ListRow key={s.id}><span className={`${partsCss.mGrow} ${listsCss.mRowText}`}><span className={listsCss.mRowTitle}>{s.name}</span><span className={listsCss.mRowNote}>{t("web-mobile.memory.offline")}</span></span></ListRow>)}
        </ListCard>
      )}
      <div style={{ height: 30 }} />
    </div>
  );
}
