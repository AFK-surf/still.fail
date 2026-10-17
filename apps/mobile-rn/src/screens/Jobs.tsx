// A chat's web services and background jobs, as the web shows them (web/src/Jobs.tsx, mobile/Chat.tsx → JobInfoRow,
// JobSheet). Jobs are mostly long-running watchers (a CI run followed, a deploy kept an eye on): what matters is whether
// each is still alive and what it last said (`stillfail-job notify`), not how long it took. Status is a small dot before the
// name and a word on the line under it; a service opens its page (Preview.tsx), a job its sheet.
import { useEffect, useRef, useState, type ReactNode } from "react";
import { PixelRatio, Pressable, ScrollView, Text, View, type StyleProp, type ViewStyle } from "react-native";
import Animated, { cancelAnimation, Easing, useAnimatedStyle, useSharedValue, withRepeat, withTiming } from "react-native-reanimated";
import type { ChatJobsView, Job, JobLogView } from "../../../../web/src/core/shapes.ts";
import { SheetSpec, useApp, type AppState, type ChatOf } from "../AppState";
import { rememberTopic, Topics } from "../data/Topics";
import { t } from "../i18n";
import { DoingMark, GroupLabel } from "../ui/Controls";
import { Icon, Icons } from "../ui/Icon";
import { Seg } from "../ui/Parts";
import { SheetGrab, SheetHead } from "../ui/Sheet";
import { Smooth } from "../ui/Smooth";
import { T } from "../ui/Text";
import { CODE_FONT, Mono, useC, withAlpha, type StillFailColors } from "../ui/Theme";
import { WaitLine, Waiting } from "../ui/Waiting";
import { InfoList, InfoRow } from "./ChatInfo";

// What a job's dot says, its word, the line under its name and every time in words are the core's (client/core-ts/src/
// jobs.ts): `tone`, `meta`, `detail`, a notice's `ago` and `clock`; a chat's all together, what matters first, is its
// `chatJobs` view.

/** What a job's dot says: a service up, a job alive, a service restarting, one that died, one that is over. */
export enum Tone { Up, Live, Restart, Fail, Off }

/** The core's word for a dot as drawn here. */
export function toneOf(word: string | null | undefined): Tone {
  switch (word) {
    case "up": return Tone.Up;
    case "live": return Tone.Live;
    case "restart": return Tone.Restart;
    case "fail": return Tone.Fail;
    default: return Tone.Off;
  }
}

/** Job.dot. */
export function dot(job: Job): Tone { return toneOf(job.tone); }

/** A tone's colour, for its dot and its word; null: the text's own. */
function toneTint(t: Tone, C: StillFailColors): string | null {
  switch (t) {
    case Tone.Up: case Tone.Live: return C.green;
    case Tone.Restart: return C.warn;
    case Tone.Fail: return C.red;
    case Tone.Off: return null;
  }
}

/** The line under a job's name: what it is up to, in a few words (its state's word coloured as its dot). Spans of a Text. */
export function metaOf(job: Job): ReactNode {
  const C = useC();
  const color = toneTint(dot(job), C);
  return (job.meta ?? []).map((part, i) => {
    switch (part.kind) {
      case "word": return color != null ? <Text key={i} style={{ color }}>{part.text}</Text> : part.text;
      case "notice": return <Text key={i} style={{ color: C.ink }}>{part.text}</Text>;
      default: return part.text;
    }
  });
}

/** A job's status: a small dot, on its name's line (a restarting service's breathes). */
export function JobDot({ tone, style }: { tone: Tone; style?: StyleProp<ViewStyle> }) {
  const C = useC();
  const breath = useSharedValue(1);
  useEffect(() => {
    if (tone === Tone.Restart) {
      // tween(700) with Compose's FastOutSlowIn, back and forth.
      breath.value = 1;
      breath.value = withRepeat(withTiming(0.35, { duration: 700, easing: Easing.bezier(0.4, 0, 0.2, 1) }), -1, true);
    } else {
      cancelAnimation(breath);
      breath.value = 1;
    }
  }, [tone, breath]);
  const breathing = useAnimatedStyle(() => ({ opacity: breath.value }));
  return (
    <View style={style}>
      <Animated.View style={[{ width: 8, height: 8, borderRadius: 4, backgroundColor: toneTint(tone, C) ?? C.subtle }, breathing]} />
    </View>
  );
}

/** A job's output as it grows: its last `lines`, as the core keeps it; `id` null reads nothing. */
export function rememberJobLog(station: string, id: string | null, lines: number): JobLogView | undefined {
  return rememberTopic<JobLogView>(id != null ? Topics.jobLog(station, id, lines) : null).value;
}

/** Stops a job from the app; a failure is said in a toast. */
export function stopJob(app: AppState, station: string, job: Job): void {
  if (!app.isDoing("job.stop", { station, id: job.id })) app.act(t("android-misc.jobs.stopWhat", { name: job.name }), () => app.api(station).stopJob(job.id));
}

/** Whether a job's stop was asked and not answered yet: its 停止 shows a spinner, not pressed again. */
export function stopping(app: AppState, station: string, job: Job): boolean {
  return app.isDoing("job.stop", { station, id: job.id });
}

/** Why a job's stop failed a moment ago, if it did: its 停止 shows a red mark (DoingMark). */
export function stopFailed(app: AppState, station: string, job: Job): string | null {
  return app.failedOf("job.stop", { station, id: job.id });
}

/** Clears a chat's jobs that are over (each session's, as the station keeps them: `clear`); a failure in a toast. */
export function clearEnded(app: AppState, station: string, sessions: string[]): void {
  if (!app.isDoing("job.clearEnded", { station })) {
    app.act(t("android-misc.jobs.clearWhat"), async () => { for (const session of sessions) await app.api(station).clearEndedJobs(session); });
  }
}

export function clearing(app: AppState, station: string): boolean {
  return app.isDoing("job.clearEnded", { station });
}
export function clearFailed(app: AppState, station: string): string | null {
  return app.failedOf("job.clearEnded", { station });
}

/** A job's row: its dot on its name's line, what it is up to under it; over ones faded. */
export function JobInfoRow({ job, onClick }: { job: Job; onClick: (() => void) | null }) {
  const C = useC();
  const off = dot(job) === Tone.Off;
  const meta = metaOf(job);
  return (
    <InfoRow onClick={onClick}>
      {/* The dot sits on the name's line: (its line height − the dot) / 2 down. */}
      <JobDot tone={dot(job)} style={{ alignSelf: "flex-start", paddingTop: 7, opacity: off ? 0.55 : 1 }} />
      <View style={{ flex: 1, minWidth: 0, opacity: off ? 0.55 : 1, gap: 1 }}>
        <T size={15} weight="500" numberOfLines={1}>{job.name}</T>
        <T size={12.5} color={C.muted} numberOfLines={1}>{meta}</T>
      </View>
      {onClick != null && <Icon icon={Icons.ChevronRight} size={14} color={C.subtle} />}
    </InfoRow>
  );
}

/**
 * Services, then background jobs. A service up or restarting opens its page; one that did not start (or is over), and
 * any job, opens what it said and its output. With `notes` each group's head says how many are up or alive.
 */
export function JobGroups({ app, station, of, view, jobs = view.jobs, notes = false }: { app: AppState; station: string; of: ChatOf; view: ChatJobsView; jobs?: Job[]; notes?: boolean }) {
  const services = jobs.filter((j) => j.service === true);
  const plain = jobs.filter((j) => j.service !== true);
  return (
    <>
      {services.length > 0 && (
        <>
          <GroupLabel text={t("android-misc.jobs.services") + (notes && view.servicesNote.length > 0 ? ` · ${view.servicesNote}` : "")} />
          <InfoList>
            {services.map((j) => {
              const up = dot(j) === Tone.Up || dot(j) === Tone.Restart;
              return <JobInfoRow key={j.id} job={j} onClick={() => { if (up) app.push({ kind: "Preview", station, job: j.id }); else openJob(app, station, of, j.id); }} />;
            })}
          </InfoList>
        </>
      )}
      {plain.length > 0 && (
        <>
          <GroupLabel text={t("android-misc.jobs.jobs") + (notes && view.jobsNote.length > 0 ? ` · ${view.jobsNote}` : "")} />
          <InfoList>{plain.map((j) => <JobInfoRow key={j.id} job={j} onClick={() => openJob(app, station, of, j.id)} />)}</InfoList>
        </>
      )}
    </>
  );
}

/** What matters now of the chat's services and jobs, from the bar's button; the rest a tap away, the ended cleared. */
export function openJobs(app: AppState, station: string, of: ChatOf) {
  app.sheet = new SheetSpec(0.62, true, null, null, false, () => <JobsSheet app={app} station={station} of={of} />);
}

function JobsSheet({ app, station, of }: { app: AppState; station: string; of: ChatOf }) {
  const C = useC();
  const topic = rememberTopic<ChatJobsView>(Topics.chatJobs(station, of));
  const [all, setAll] = useState(false);
  useApp((s) => s.doing);
  const isClearing = clearing(app, station);
  const whyNotCleared = clearFailed(app, station);
  const view = topic.value;
  // Not here yet: its rows to come, not an empty sheet (that says there are none).
  if (view == null) {
    return (
      <>
        <SheetGrab />
        <SheetHead title={t("android-misc.jobs.title")} />
        <Waiting count={3} error={topic.error?.message ?? null} style={{ flex: 1 }} />
      </>
    );
  }
  const jobs = view.jobs;
  const shown = all ? jobs : jobs.filter((j) => j.current === true);
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("android-misc.jobs.title")} />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingLeft: 18, paddingRight: 18, paddingBottom: 30 }}>
        {jobs.length === 0 && (
          <View style={{ paddingHorizontal: 2, paddingVertical: 12, gap: 4 }}>
            <T size={15} weight="600">{t("android-misc.jobs.none")}</T>
            <T size={13} color={C.muted}>{t("android-misc.jobs.none.text")}</T>
          </View>
        )}
        {jobs.length > 0 && shown.length === 0 && <T size={13} color={C.muted} style={{ paddingHorizontal: 20, paddingVertical: 8 }}>{t("android-misc.jobs.noneNow")}</T>}
        <JobGroups app={app} station={station} of={of} view={view} jobs={shown} notes />
        {jobs.length > view.current && (
          <SheetLink onClick={() => setAll((a) => !a)}>
            {all ? <T size={14} color={C.accent}>{t("android-misc.jobs.onlyNow")}</T> : (
              <>
                <T size={14} color={C.accent}>{view.allText}</T>
                <T size={12} color={C.muted}>{view.hiddenText}</T>
              </>
            )}
          </SheetLink>
        )}
        {view.ended > 0 && (
          <SheetLink onClick={() => clearEnded(app, station, view.clear)}>
            <View style={{ flexDirection: "row", alignItems: "center", gap: 6, alignSelf: "flex-start" }}>
              <T size={14} color={C.accent}>{view.clearText}</T>
              <DoingMark running={isClearing} failed={whyNotCleared} inline />
            </View>
          </SheetLink>
        )}
      </ScrollView>
    </>
  );
}

/** A quiet text button under the groups (web mobile's mJobsAll). */
function SheetLink({ onClick, children }: { onClick: () => void; children?: ReactNode }) {
  const C = useC();
  return (
    <View style={{ paddingTop: 14, alignSelf: "flex-start" }}>
      <Smooth radius={8}>
        <Pressable onPress={onClick} android_ripple={{ color: withAlpha(C.ink, 0.1) }} style={{ paddingHorizontal: 2, paddingVertical: 6, gap: 2 }}>
          {children}
        </Pressable>
      </Smooth>
    </View>
  );
}

/** A job, from the chat's sheet: what it said, or its output as it grows; stopped from here. */
export function openJob(app: AppState, station: string, of: ChatOf, id: string) {
  app.sheet = new SheetSpec(0.8, true, null, null, false, () => <JobSheet app={app} station={station} of={of} id={id} />);
}

function JobSheet({ app, station, of, id }: { app: AppState; station: string; of: ChatOf; id: string }) {
  const C = useC();
  const topic = rememberTopic<ChatJobsView>(Topics.chatJobs(station, of));
  const job = topic.value?.jobs?.find((j) => j.id === id);
  const [picked, setPicked] = useState(0);
  const tab = job?.service === true ? 1 : picked;
  const log = rememberJobLog(station, job != null && tab === 1 ? id : null, 300);
  // The last line it wrote, as it grows.
  const last = rememberJobLog(station, job != null && tab === 0 ? id : null, 1);
  return (
    <>
      <SheetGrab />
      {job == null ? (
        <>
          <SheetHead title={t("android-misc.jobs.job")} />
          {topic.value != null
            ? <T size={14} color={C.muted} style={{ paddingHorizontal: 18 }}>{t("android-misc.jobs.gone")}</T>
            : <WaitLine text={topic.error?.message ?? t("common.reading")} error={topic.error != null} style={{ paddingHorizontal: 18 }} />}
        </>
      ) : <JobBody app={app} station={station} job={job} tab={tab} onTab={setPicked} log={log} last={last} />}
    </>
  );
}

/** A job's sheet under its grabber: its name and state, what it said or its output, and stop while it runs. */
function JobBody({ app, station, job, tab, onTab, log, last }: { app: AppState; station: string; job: Job; tab: number; onTab: (tab: number) => void; log: JobLogView | undefined; last: JobLogView | undefined }) {
  const C = useC();
  const running = job.state === "running";
  const meta = metaOf(job);
  useApp((s) => s.doing);
  const isStopping = stopping(app, station, job);
  const whyNotStopped = stopFailed(app, station, job);
  return (
    <>
      <View style={{ flexDirection: "row", paddingLeft: 22, paddingRight: 22, paddingTop: 4, paddingBottom: 14, gap: 12 }}>
        <JobDot tone={dot(job)} style={{ paddingTop: 8 }} />
        <View style={{ flex: 1, minWidth: 0 }}>
          <T size={16} weight="600">{job.name}</T>
          <T size={12.5} color={C.muted} numberOfLines={1}>{meta}</T>
        </View>
      </View>
      <View style={{ flex: 1, paddingLeft: 18, paddingRight: 18, paddingBottom: 24, gap: 14 }}>
        {job.command != null && job.command.trim() !== "" && <T size={11.5} line={17} color={C.muted} mono>{job.command}</T>}
        {/* A service has only its output to show. */}
        {job.service !== true && <Seg options={[t("android-misc.jobs.notices"), t("android-misc.jobs.output")]} selected={tab} onSelect={onTab} style={{ alignSelf: "stretch" }} height={34} fill />}
        {tab === 0 ? <Notices job={job} last={last} /> : <Output log={log} />}
        {running && (
          <Smooth radius={23} style={{ alignSelf: "stretch", height: 46, backgroundColor: withAlpha(C.red, 0.12) }}>
            <Pressable
              disabled={isStopping}
              onPress={() => stopJob(app, station, job)}
              android_ripple={{ color: withAlpha(C.ink, 0.1) }}
              style={{ flex: 1, flexDirection: "row", gap: 6, justifyContent: "center", alignItems: "center" }}
            >
              {isStopping || whyNotStopped != null ? <DoingMark running={isStopping} failed={whyNotStopped} /> : <Icon icon={Icons.Stop} size={16} color={C.red} />}
              <T size={15} weight="500" color={C.red}>{t("android-misc.jobs.stop")}</T>
            </Pressable>
          </Smooth>
        )}
      </View>
    </>
  );
}

/** What it said, newest first, and when its output last grew with its last line. */
function Notices({ job, last }: { job: Job; last: JobLogView | undefined }) {
  const C = useC();
  const notices = job.notices ?? [];
  const said = last != null ? last.said : job.outputSaid;
  const line = last?.last;
  return (
    <>
      <ScrollView style={{ flexGrow: 0, flexShrink: 1 }} contentContainerStyle={{ gap: 12 }}>
        {notices.length === 0 && <T size={13} color={C.muted} style={{ paddingHorizontal: 20, paddingVertical: 8 }}>{t("android-misc.jobs.noNotices")}</T>}
        {notices.map((n, i) => (
          <View key={`${n.at}-${i}`} style={{ flexDirection: "row", gap: 10 }}>
            <T size={14} color={C.subtle} style={{ width: 48 }}>{n.clock ?? ""}</T>
            <T size={14} style={{ flex: 1, minWidth: 0 }}>{n.text}</T>
          </View>
        ))}
      </ScrollView>
      {said != null && (
        <View style={{ gap: 2 }}>
          <T size={11} color={C.subtle}>{said}</T>
          {line != null && <T size={11.5} line={Mono.lineHeight} color={C.muted} mono numberOfLines={1}>{line}</T>}
        </View>
      )}
    </>
  );
}

/** Its output, kept at its end as it grows unless scrolled up from there. */
function Output({ log }: { log: JobLogView | undefined }) {
  const C = useC();
  const scroll = useRef<ScrollView>(null);
  // Where the list stands (dp): how far scrolled, how tall what it holds, how tall it is.
  const at = useRef({ offset: 0, content: 0, frame: 0 });
  const text = log?.text;
  const lastText = useRef<string | undefined>(undefined);
  const follow = useRef(false);
  if (text !== lastText.current) {
    lastText.current = text;
    // Within 60 px of its end before the new text is laid out: kept at its end once it is.
    const a = at.current;
    follow.current = (Math.max(0, a.content - a.frame) - a.offset) * PixelRatio.get() < 60;
  }
  return (
    <Smooth radius={16} style={{ alignSelf: "stretch", flexGrow: 0, flexShrink: 1, minHeight: 120, backgroundColor: withAlpha(C.ink, 0.05) }}>
      <ScrollView
        ref={scroll}
        style={{ flexGrow: 0, flexShrink: 1, minHeight: 120 }}
        contentContainerStyle={{ paddingHorizontal: 14, paddingVertical: 12 }}
        scrollEventThrottle={16}
        onScroll={(e) => { at.current.offset = e.nativeEvent.contentOffset.y; }}
        onLayout={(e) => { at.current.frame = e.nativeEvent.layout.height; }}
        onContentSizeChange={(_w, h) => {
          at.current.content = h;
          if (follow.current) { follow.current = false; scroll.current?.scrollToEnd({ animated: false }); }
        }}
      >
        {log == null ? <WaitLine /> : <T size={11.5} line={Mono.lineHeight} style={{ fontFamily: CODE_FONT }}>{text === "" ? t("android-misc.jobs.noOutput") : (text ?? "")}</T>}
      </ScrollView>
    </Smooth>
  );
}
