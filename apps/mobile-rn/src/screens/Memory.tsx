// The agents' memory on a station, in two layers, shown as it is (the agents write it), as the web's Memory.tsx has
// it: the global memory (what holds across projects, read at every session's start) and each project's memory, a skill
// whose description starts with 项目记忆： and says when it applies (its whole text is read when a task matches). The
// station's other skills are listed too. A page lists them (the global memory by its parts, a row for each skill), and
// each opens on a page of its own to be read: a skill with its other files, the global memory a part at a time.
import { useEffect, useState } from "react";
import { Pressable, ScrollView, Text, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { useTopic } from "../../../../web/src/core/react.ts";
import type { MemorySection, SkillFile, StationMemory, StationView } from "../../../../web/src/core/shapes.ts";
import { useDoing, useDoingFailed } from "../../../../web/src/doing.ts";
import { app } from "../AppState";
import type { WorkspaceEntry } from "../data/Accounts";
import { Topics } from "../data/Topics";
import { t } from "../i18n";
import { stationName } from "../ui/ChatInk";
import { DoingMark } from "../ui/Controls";
import { Icon, Icons } from "../ui/Icon";
import { Markdown } from "../ui/Markdown";
import { Card, LargeTitle, ListCard, ListRow, NavBar, SectionHeader } from "../ui/Parts";
import { T } from "../ui/Text";
import { useC, withAlpha } from "../ui/Theme";
import { WaitShape, Waiting } from "../ui/Waiting";
import { Switch } from "./Connects";
import { GoRow, PageNote } from "./SettingParts";
import { TopBack } from "./Stations";

/** The last memory read of each station, so a page opened from the list has it at once (it is read again). */
const kept = new Map<string, StationMemory>();

interface MemoryRead { memory: StationMemory | undefined; error: string | null; reload: () => void }

/** A station's memory, read as a page opens (it changes as agents write it, not while it is looked at) and after a
 * skill's sharing changed here, or why it could not be. */
function rememberMemory(address: string): MemoryRead {
  const [read, setRead] = useState<{ address: string; memory: StationMemory | undefined; error: string | null }>(() => ({ address, memory: kept.get(address), error: null }));
  const [round, setRound] = useState({ address, n: 0 });
  // Another station: from what was kept of it, its rounds from the start.
  const now = read.address === address ? read : { address, memory: kept.get(address), error: null };
  if (read.address !== address) setRead(now);
  if (round.address !== address) setRound({ address, n: 0 });
  useEffect(() => {
    let live = true;
    (async () => {
      try {
        const m = (await app.api(address).memory()) as StationMemory;
        kept.set(address, m);
        if (live) setRead({ address, memory: m, error: null });
      } catch (e) {
        if (live) setRead((r) => ({ ...r, address, error: e instanceof Error ? e.message : String(e) }));
      }
    })();
    return () => { live = false; };
  }, [address, round.n]);
  return { memory: now.memory, error: now.error, reload: () => setRound((r) => ({ address, n: r.n + 1 })) };
}

/** The global memory's parts (all of it in one, from a core before them). */
function sectionsOf(m: StationMemory): MemorySection[] {
  const text = m.global.text.trim();
  const sections = m.global.sections ?? [];
  if (sections.length > 0) return sections;
  return text.length === 0 ? [] : [{ title: t("android-misc.memory.global"), text, note: "" }];
}

/** What a skill is for in a line, for its row (the core's; a core before it: when it applies, whole). */
const lineOf = (k: SkillFile) => k.brief ?? k.about ?? k.description;

export function MemoryScreen({ current, address }: { current: WorkspaceEntry; address: string }) {
  const C = useC();
  const insets = useSafeAreaInsets();
  const stations = useTopic<StationView[]>(Topics.stations(current.workspace.id));
  const s = stations.value?.find((x) => x.station === address);
  const names = new Map((stations.value ?? []).map((x) => [x.id, x.name] as const));
  const read = rememberMemory(address);
  const [builtin, setBuiltin] = useState({ address, open: false });
  const builtinOpen = builtin.address === address && builtin.open;
  const m = read.memory;
  const bar = (
    <NavBar back={s?.name ?? stationName(address)} onBack={() => app.pop()} title={t("android-misc.memory.title")}
      sub={<T size={11} color={C.muted} numberOfLines={1} ellipsizeMode="clip">{t("android-misc.memory.sub")}</T>} />
  );
  if (m == null) return (
    <View style={{ flex: 1 }}>
      {bar}
      <Waiting shape={WaitShape.Cards} text={t("common.reading")} error={read.error != null ? t("android-misc.memory.loadFailed", { error: read.error }) : undefined} />
    </View>
  );
  const sections = sectionsOf(m);
  const projects = m.skills.filter((k) => k.project);
  const skills = m.skills.filter((k) => !k.project && !k.builtin);
  const builtins = m.skills.filter((k) => !k.project && k.builtin);
  const skillRow = (k: SkillFile) => (
    <MemoryRow key={k.name} title={k.name} sub={lineOf(k) || t("android-misc.memory.noWhen")} value={k.size ?? null} tag={tagOf(k, names)}
      onClick={() => app.push({ kind: "MemoryDoc", station: address, skill: k.name })} />
  );
  return (
    <View style={{ flex: 1 }}>
      {bar}
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingTop: 4, paddingBottom: insets.bottom }}>
        <SectionHeader title={t("android-misc.memory.global")} trailing={[t("web-main.memory.global.when"), m.global.size ?? null].filter((x): x is string => x != null).join(" · ")} start={24} />
        {sections.length === 0
          ? <Note text={t("android-misc.memory.empty")} />
          : <ListCard>{sections.map((p, i) => <MemoryRow key={i} title={p.title} sub={null} value={p.note || null} onClick={() => app.push({ kind: "MemoryDoc", station: address, skill: null, at: i })} />)}</ListCard>}
        <SectionHeader title={t("android-misc.memory.projects")} trailing={t("web-main.memory.projects.when")} start={24} />
        {projects.length === 0
          ? <Note text={t("android-misc.memory.projects.none")} />
          : <ListCard>{projects.map(skillRow)}</ListCard>}
        {(skills.length > 0 || builtins.length > 0) && (
          <>
            <SectionHeader title={t("android-misc.memory.skills")} start={24} />
            <ListCard>
              {skills.map(skillRow)}
              {builtins.length > 0 && (
                <MemoryRow
                  title={t("android-misc.memory.builtin")}
                  sub={builtinOpen ? null : builtins.map((k) => k.name).join(t("web-main.list.separator"))}
                  value={t("web-main.memory.count", { n: builtins.length })}
                  open={builtinOpen}
                  onClick={() => setBuiltin({ address, open: !builtinOpen })}
                />
              )}
              {builtinOpen && builtins.map(skillRow)}
            </ListCard>
          </>
        )}
        <View style={{ height: 30 }} />
      </ScrollView>
    </View>
  );
}

/** Whose a skill is, after its name: another station's, or shared from here. */
function tagOf(skill: SkillFile, names: Map<string, string>): string | null {
  switch (skill.share?.role) {
    case "user": {
      const host = skill.share?.host ?? "";
      return t("web-main.memory.share.from", { station: names.get(host) ?? host.slice(0, 8) });
    }
    case "host": return t("web-main.memory.share.shared");
    default: return null;
  }
}

/** A row that opens a page (or, `open` given, folds a group open): its name and whose, a line under it, how much is in it. */
function MemoryRow({ title, sub, value, tag = null, open = null, onClick }: { title: string; sub: string | null; value: string | null; tag?: string | null; open?: boolean | null; onClick: () => void }) {
  const C = useC();
  return (
    <ListRow onClick={onClick}>
      <View style={{ flex: 1, minWidth: 0 }}>
        <View style={{ flexDirection: "row", alignItems: "center", gap: 8 }}>
          <T size={15} color={C.ink} numberOfLines={1} style={{ flexShrink: 1, minWidth: 0 }}>{title}</T>
          {tag != null && <T size={12} color={C.subtle} numberOfLines={1} ellipsizeMode="clip">{tag}</T>}
        </View>
        {sub != null && <T size={13} color={C.muted} numberOfLines={1}>{sub}</T>}
      </View>
      {value != null && <T size={13} color={C.muted} numberOfLines={1} ellipsizeMode="clip" style={{ maxWidth: 120 }}>{value}</T>}
      <Icon icon={open === true ? Icons.ChevronDown : Icons.ChevronRight} size={14} color={C.subtle} />
    </ListRow>
  );
}

/** One of a station's memory pages: a skill with when it is read, its sharing and its files (`skill`), or the global
 * memory a part at a time (from `at`). */
export function MemoryDocScreen({ current, address, skill, at }: { current: WorkspaceEntry; address: string; skill: string | null; at: number }) {
  void current;
  const C = useC();
  const insets = useSafeAreaInsets();
  const read = rememberMemory(address);
  const [pick, setPick] = useState({ address, skill, picked: at });
  const picked = pick.address === address && pick.skill === skill ? pick.picked : at;
  const setPicked = (i: number) => setPick({ address, skill, picked: i });
  const m = read.memory;
  const k = skill == null ? undefined : m?.skills.find((x) => x.name === skill);
  const sub = skill == null ? t("web-main.memory.global.when")
    : k == null ? null
    : k.project ? t("android-misc.memory.projects")
    : k.builtin ? t("android-misc.memory.builtin")
    : t("web-main.memory.skill");
  const bar = (
    <NavBar back={t("android-misc.memory.title")} onBack={() => app.pop()} title={skill ?? t("android-misc.memory.global")}
      sub={sub != null ? <T size={11} color={C.muted} numberOfLines={1} ellipsizeMode="clip">{sub}</T> : undefined} />
  );
  if (m == null) return (
    <View style={{ flex: 1 }}>
      {bar}
      <Waiting shape={WaitShape.Cards} text={t("common.reading")} error={read.error != null ? t("android-misc.memory.loadFailed", { error: read.error }) : undefined} />
    </View>
  );
  // Read, and the skill is not in it (taken away since): said, not waited on.
  if (skill != null && k == null) return (
    <View style={{ flex: 1 }}>
      {bar}
      <T size={14} color={C.muted} style={{ padding: 24 }}>{t("web-main.memory.gone")}</T>
    </View>
  );
  let body;
  if (k == null) {
    const sections = sectionsOf(m);
    const i = Math.min(Math.max(picked, 0), Math.max(sections.length - 1, 0));
    body = (
      <>
        <DocChips items={sections.map((p) => [p.title, p.note])} picked={i} onPick={setPicked} />
        <Card><Markdown text={sections[i]?.text || t("android-misc.memory.empty")} size={14} /></Card>
      </>
    );
  } else {
    const pages: [string, string | null, string][] = [
      [t("web-main.memory.overview"), null, k.body ?? k.text],
      ...(k.files ?? []).map((f) => [f.label ?? f.name, f.size ?? null, f.text] as [string, string | null, string]),
    ];
    const i = Math.min(Math.max(picked, 0), pages.length - 1);
    body = (
      <>
        <Card>
          <T size={12} weight="500" color={C.subtle}>{t("web-main.memory.when")}</T>
          <T size={13} color={C.muted} style={{ paddingTop: 2 }}>{(k.about ?? k.description) || t("android-misc.memory.noWhen")}</T>
          {!k.builtin && k.share?.role !== "user" && <ShareRow skill={k} station={address} changed={read.reload} />}
        </Card>
        <DocChips items={pages.map((p) => [p[0], p[1]])} picked={i} onPick={setPicked} />
        <Card><Markdown text={pages[i]![2] || t("android-misc.memory.empty")} size={14} /></Card>
      </>
    );
  }
  return (
    <View style={{ flex: 1 }}>
      {bar}
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingTop: 4, paddingBottom: insets.bottom }}>
        {body}
        <View style={{ height: 30 }} />
      </ScrollView>
    </View>
  );
}

/** Whether a skill of this station's is shared with the workspace's other stations, and the edits two made at once. */
function ShareRow({ skill, station, changed }: { skill: SkillFile; station: string; changed: () => void }) {
  const C = useC();
  const busy = useDoing("skill.share", { station, name: skill.name });
  const failed = useDoingFailed("skill.share", { station, name: skill.name });
  const on = skill.share?.role === "host";
  const conflicts = skill.share?.conflicts ?? [];
  return (
    <>
      <Pressable
        disabled={busy}
        onPress={() => app.act(t("web-main.memory.share.switch"), async () => { await app.api(station).shareSkill(skill.name, !on); changed(); })}
        android_ripple={{ color: withAlpha(C.ink, 0.1) }}
        style={{ alignSelf: "stretch", marginTop: 12, flexDirection: "row", alignItems: "center", gap: 10 }}
      >
        <T size={14} color={C.ink} style={{ flex: 1, minWidth: 0 }}>{t("web-main.memory.share.switch")}</T>
        <DoingMark running={busy} failed={failed ?? null} />
        <Switch on={on} />
      </Pressable>
      {conflicts.length > 0 && (
        <T size={12} color={C.warn} style={{ paddingTop: 6 }}>{t("web-main.memory.share.conflicts", { names: conflicts.join(t("web-main.list.separator")) })}</T>
      )}
    </>
  );
}

/** Pages to pick between, as a row of pills scrolled across when they do not fit (none for a single page): a skill's
 * files, the global memory's parts; each with how much is in it. */
function DocChips({ items, picked, onPick }: { items: [string, string | null][]; picked: number; onPick: (i: number) => void }) {
  const C = useC();
  if (items.length < 2) return null;
  return (
    <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ alignSelf: "stretch", flexGrow: 0 }} contentContainerStyle={{ paddingLeft: 12, paddingRight: 12, paddingBottom: 10, gap: 6 }}>
      {items.map(([label, note], i) => {
        const on = i === picked;
        return (
          <View key={i} style={{ borderRadius: 999, overflow: "hidden", backgroundColor: on ? C.ink : C.chip }}>
            <Pressable onPress={() => onPick(i)} android_ripple={{ color: withAlpha(C.ink, 0.1) }} style={{ paddingHorizontal: 14, paddingVertical: 7 }}>
              <T size={13} color={on ? C.bg : C.ink} numberOfLines={1} ellipsizeMode="clip">
                <Text style={{ fontWeight: on ? "600" : "400" }}>{label}</Text>
                {note != null && note.length > 0 && <Text style={{ color: withAlpha(on ? C.bg : C.ink, 0.6) }}>{`  ${note}`}</Text>}
              </T>
            </Pressable>
          </View>
        );
      })}
    </ScrollView>
  );
}

/**
 * The memory of every station, from settings (SettingsHome.tsx), as the narrow web's MemoriesScreen: a row for each,
 * opening its memory (above); memory is kept on each station and not shared between them.
 */
export function MemoriesScreen({ current }: { current: WorkspaceEntry }) {
  const C = useC();
  const insets = useSafeAreaInsets();
  const topic = useTopic<StationView[]>(Topics.stations(current.workspace.id));
  const stations = topic.value;
  return (
    <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: insets.bottom }}>
      <TopBack label={t("android-misc.settings")} onBack={() => app.pop()} />
      <LargeTitle small="" big={t("android-misc.memory.title")} />
      <PageNote text={t("android-misc.memory.note")} />
      {stations == null
        ? <Waiting shape={WaitShape.Rows} count={3} text={t("common.readingStations")} error={topic.error?.message} />
        : (
          <ListCard>
            {stations.map((s) => s.online
              ? <GoRow key={s.station} title={s.name} value={t("android-misc.memory.row")} onClick={() => app.push({ kind: "Memory", station: s.station })} />
              : (
                <ListRow key={s.station}>
                  <View style={{ flex: 1, minWidth: 0 }}>
                    <T size={15} color={C.ink}>{s.name}</T>
                    <T size={13} color={C.muted}>{t("android-misc.memory.offline")}</T>
                  </View>
                </ListRow>
              ))}
          </ListCard>
        )}
      <View style={{ height: 30 }} />
    </ScrollView>
  );
}

function Note({ text }: { text: string }) {
  const C = useC();
  return <T size={13} color={C.muted} style={{ paddingHorizontal: 24, paddingBottom: 8 }}>{text}</T>;
}
