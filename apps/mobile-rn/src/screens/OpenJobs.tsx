// The services and background jobs left up a long while (an hour), across the chats of the workspace's stations, so
// none is forgotten running (web/src/OpenJobs.tsx, at the desktop sidebar's foot; here at the top of the list, which is
// what a phone sees first): web services and background jobs, each under its heading; nothing at all while there are
// none. Each leads to its chat (a service opens over it) and stops from here. The core puts them together (its
// `longJobs` view, from each station's `jobs`, current with its events).
import { useState } from "react";
import { Pressable, View } from "react-native";
import type { Job, LongJobsGroup, LongJobsView } from "../../../../web/src/core/shapes.ts";
import { app, useApp } from "../AppState";
import { ChatOf, Topics, rememberTopic } from "../data/Topics";
import { t } from "../i18n";
import { DoingMark } from "../ui/Controls";
import { Icon, Icons } from "../ui/Icon";
import { Smooth } from "../ui/Smooth";
import { T } from "../ui/Text";
import { useC, withAlpha } from "../ui/Theme";
import { JobDot, dot, stopFailed, stopJob, stopping } from "./Jobs";

/** Rows shown before the rest folds under「还有 N 个」. */
const SHOWN = 3;

/** The list's reminder of what is left up on the workspace's (`scope`) stations: nothing while there is none. */
export function OpenJobs({ scope }: { scope: string }) {
  const view = rememberTopic<LongJobsView>(Topics.longJobs(scope));
  const groups = view.value?.groups ?? [];
  const [all, setAll] = useState<Record<string, boolean>>({});
  if (groups.length === 0) return null;
  return (
    <View style={{ paddingLeft: 10, paddingRight: 10, paddingTop: 4, paddingBottom: 10, gap: 8 }}>
      {groups.map((g) => <OpenGroup key={g.key} group={g} all={all} onAll={(key) => setAll((a) => ({ ...a, [key]: true }))} />)}
    </View>
  );
}

function OpenGroup({ group, all, onAll }: { group: LongJobsGroup; all: Record<string, boolean>; onAll: (key: string) => void }) {
  const C = useC();
  const list = group.jobs;
  const shown = all[group.key] === true || list.length <= SHOWN + 1 ? list : list.slice(0, SHOWN);
  return (
    <View style={{ gap: 2 }}>
      <T size={12} color={C.muted} style={{ paddingHorizontal: 10, paddingVertical: 2 }}>{group.head}</T>
      {shown.map((job) => <OpenRow key={`${job.station ?? ""}/${job.id}`} job={job} />)}
      {shown.length < list.length && (
        <Smooth radius={8} style={{ alignSelf: "flex-start" }}>
          <Pressable onPress={() => onAll(group.key)} android_ripple={{ color: withAlpha(C.ink, 0.1) }} style={{ paddingHorizontal: 10, paddingVertical: 3 }}>
            <T size={12} color={C.muted}>{t("android-misc.openJobs.more", { n: list.length - shown.length })}</T>
          </Pressable>
        </Smooth>
      )}
    </View>
  );
}

/** A job: the row leads to its chat (a service opens over it); stop at its end (no hover here: it always shows). */
function OpenRow({ job }: { job: Job }) {
  const C = useC();
  const chat = job.chat;
  // What is under way (the core's doing list, in the app's state): the row drawn again as it changes.
  useApp((s) => s.doing);
  const isStopping = stopping(app, job.station ?? "", job);
  const failed = stopFailed(app, job.station ?? "", job);
  const station = job.station;
  if (station === undefined) return null;
  return (
    <Smooth radius={10}>
      <Pressable
        disabled={chat === undefined}
        onPress={() => {
          if (!chat) return;
          app.push({ kind: "Chat", station, of: ChatOf.Session(chat.id) });
          if (job.service === true) app.push({ kind: "Preview", station, job: job.id });
        }}
        android_ripple={chat !== undefined ? { color: withAlpha(C.ink, 0.1) } : undefined}
        style={{ flexDirection: "row", alignItems: "center", gap: 10, paddingLeft: 10, paddingRight: 4, paddingTop: 5, paddingBottom: 5 }}
      >
        {/* The dot, in the column the rows' icons take. */}
        <View style={{ width: 16, alignItems: "center", justifyContent: "center" }}><JobDot tone={dot(job)} /></View>
        <View style={{ flex: 1, minWidth: 0 }}>
          <T size={14} line={18} color={C.ink} numberOfLines={1} ellipsizeMode="tail">{job.name}</T>
          <T size={12} line={16} color={C.muted} numberOfLines={1} ellipsizeMode="tail">{`${job.whereText ?? ""} · ${job.age ?? ""}`}</T>
        </View>
        <Pressable
          disabled={isStopping}
          onPress={() => stopJob(app, station, job)}
          accessibilityLabel={t("android-misc.jobs.stopNamed", { name: job.name })}
          android_ripple={{ color: withAlpha(C.ink, 0.1), borderless: false }}
          style={{ width: 32, height: 32, borderRadius: 16, overflow: "hidden", alignItems: "center", justifyContent: "center" }}
        >
          {isStopping || failed != null ? <DoingMark running={isStopping} failed={failed ?? null} /> : <Icon icon={Icons.Stop} size={15} color={C.muted} />}
        </Pressable>
      </Pressable>
    </Smooth>
  );
}
