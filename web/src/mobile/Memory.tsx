// The agents' memory on a station on a narrow screen, as the Android app has it (apps/android/…/screens/Memory.kt), from
// the station's page: the wide screen's parts (../Memory.tsx: useMemory, memoryParts) as a list under section headers,
// the global memory by its parts and a row for each skill, each opening a page of its own to be read.
import { useState } from "react";
import { useParams, useSearchParams } from "react-router";
import { DocChips, MEMORY_TEXT, SkillShare, SkillTags, memoryParts, skillBrief, skillKind, skillPages, useMemory, type SkillFile } from "../Memory.tsx";
import { Prose } from "../Prose.tsx";
import { useStation } from "../station.tsx";
import { useApp } from "./app.tsx";
import { useStations } from "../api.ts";
import { ChevronDown, ChevronRight } from "@stillfail/ui/icons.tsx";
import { Card, LargeTitle, ListCard, ListRow, Loading, NavBar, SectionHeader, TopBack } from "./parts.tsx";
import { GoRow } from "./Settings.tsx";
import * as settingsCss from "./styles/settings.css.ts";
import * as settingsRowCss from "./Settings.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as listsCss from "./styles/lists.css.ts";
import * as css from "./Memory.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as rootCss from "./styles/root.css.ts";
import * as barsCss from "./styles/bars.css.ts";
import * as conversationCss from "../styles/conversation.css.ts";
import { t } from "../i18n.ts";

/** A row that opens a page: its name (and whose), a line under it, how much is in it. */
function MemoryRow({ title, sub, value, tags, open, onClick }: { title: string; sub?: string | undefined; value?: string | undefined; tags?: React.ReactNode; open?: boolean; onClick: () => void }) {
  return (
    <ListRow onClick={onClick}>
      <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
        <span className={css.mMemoryTitle}><span className={listsCss.mRowTitle}>{title}</span>{tags}</span>
        {sub && <span className={listsCss.mRowNote}>{sub}</span>}
      </span>
      {value && <span className={settingsRowCss.mValue}>{value}</span>}
      {open === undefined ? <ChevronRight size={14} className={partsCss.mSubtle} /> : open ? <ChevronDown size={14} className={partsCss.mSubtle} /> : <ChevronRight size={14} className={partsCss.mSubtle} />}
    </ListRow>
  );
}

export function MemoryScreen() {
  const app = useApp();
  const station = useStation();
  const { station: id = "" } = useParams();
  const { memory, error } = useMemory(station.address);
  const [builtinOpen, setBuiltinOpen] = useState(false);
  const go = (page: string) => app.push(app.at(`/s/${id}/memory/${page}`));
  const skillRow = (s: SkillFile) => (
    <MemoryRow key={s.name} title={s.name} sub={skillBrief(s) || t("web-main.memory.noWhen")} value={s.size} onClick={() => go(`skill/${encodeURIComponent(s.name)}`)}
      tags={<SkillTags skill={s} station={station.address} className={css.mMemoryTag} />} />
  );
  const parts = memory && memoryParts(memory);
  return (
    <div className={pagesCss.mScreen}>
      <NavBar back={station.name} onBack={app.pop} title={t("web-mobile.settings.memory")} sub={<span className={barsCss.mNavbarNote}>{t("web-mobile.memory.sub")}</span>} />
      {!memory || !parts ? <Loading text={error ? MEMORY_TEXT.failed(error) : t("web-mobile.reading")} /> : (
        <div className={pagesCss.mScroll} style={{ paddingTop: 4 }}>
          <SectionHeader title={t("web-mobile.memory.global")} trailing={[t("web-main.memory.global.when"), memory.global.size].filter(Boolean).join(" · ")} start={24} />
          {parts.sections.length === 0 ? <p className={css.mMemoryNote}>{t("web-mobile.memory.empty")}</p>
            : <ListCard>{parts.sections.map((p, i) => <MemoryRow key={i} title={p.title} value={p.note} onClick={() => go(`global?at=${i}`)} />)}</ListCard>}
          <SectionHeader title={t("web-mobile.memory.projects")} trailing={t("web-main.memory.projects.when")} start={24} />
          {parts.projects.length === 0 ? <p className={css.mMemoryNote}>{MEMORY_TEXT.none}</p> : <ListCard>{parts.projects.map(skillRow)}</ListCard>}
          {parts.skills.length + parts.builtin.length > 0 && (
            <>
              <SectionHeader title={t("web-mobile.memory.others")} start={24} />
              <ListCard>
                {parts.skills.map(skillRow)}
                {parts.builtin.length > 0 && <MemoryRow title={t("web-main.memory.builtin")} open={builtinOpen} onClick={() => setBuiltinOpen(!builtinOpen)}
                  sub={builtinOpen ? undefined : parts.builtin.map((s) => s.name).join(t("web-main.list.separator"))} value={t("web-main.memory.count", { n: parts.builtin.length })} />}
                {builtinOpen && parts.builtin.map(skillRow)}
              </ListCard>
            </>
          )}
          <div style={{ height: 30 }} />
        </div>
      )}
    </div>
  );
}

/** One of a station's memory pages (s/:station/memory/global?at= or /skill/:name): a skill with when it is read, its
 * sharing and its files, or the global memory a part at a time. */
export function MemoryDocScreen() {
  const app = useApp();
  const station = useStation();
  const { name } = useParams();
  const [q] = useSearchParams();
  const { memory, error, reload } = useMemory(station.address);
  const [at, setAt] = useState(() => Number(q.get("at") ?? 0));
  const skill = name === undefined ? null : memory?.skills.find((s) => s.name === name);
  const doc = (text: string) => <Card><div className={`${rootCss.wide} ${conversationCss.markdown} ${css.mMemoryDoc}`}><Prose>{text}</Prose></div></Card>;
  const sub = name === undefined ? t("web-main.memory.global.when") : skill ? skillKind(skill) : undefined;
  let body: React.ReactNode;
  if (!memory) body = <Loading text={error ? MEMORY_TEXT.failed(error) : t("web-mobile.reading")} />;
  else if (name === undefined) {
    const { sections } = memoryParts(memory);
    const i = Math.min(Math.max(0, at), Math.max(0, sections.length - 1));
    body = (
      <>
        <DocChips items={sections.map((p) => ({ label: p.title, note: p.note }))} picked={i} onPick={setAt} className={css.mMemoryChips} chip={css.mMemoryChip} />
        {doc(sections[i]?.text || t("web-mobile.memory.empty"))}
      </>
    );
  } else if (!skill) body = <Loading text={t("web-main.memory.gone")} />;
  else {
    const pages = skillPages(skill);
    const i = Math.min(at, pages.length - 1);
    body = (
      <>
        <Card>
          <div className={css.mMemoryWhen}><b>{t("web-main.memory.when")}</b>{(skill.about ?? skill.description) || t("web-main.memory.noWhen")}</div>
          {!skill.builtin && skill.share?.role !== "user" && <div className={css.mMemoryShare}><SkillShare skill={skill} station={station.address} changed={reload} /></div>}
        </Card>
        <DocChips items={pages.map((p) => ({ label: p.label, note: p.size }))} picked={i} onPick={setAt} className={css.mMemoryChips} chip={css.mMemoryChip} />
        {doc(pages[i]!.text)}
      </>
    );
  }
  return (
    <div className={pagesCss.mScreen}>
      <NavBar back={t("web-mobile.settings.memory")} onBack={app.pop} title={name ?? t("web-mobile.memory.global")} sub={sub && <span className={barsCss.mNavbarNote}>{sub}</span>} />
      {memory ? <div className={pagesCss.mScroll} style={{ paddingTop: 4 }}>{body}<div style={{ height: 30 }} /></div> : body}
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
