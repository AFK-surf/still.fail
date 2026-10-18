// 设置 › 归档, as the wide screen's page and the phone's screen show it alike: whether a done chat suggests archiving
// it (this device's `archiveHint`), and how each station archives chats on its own (its `archiving`, its managers'),
// beside whether its archive review is on (自动决策).
import type { ArchivingView, StationView } from "./core/shapes.ts";
import { stationApi, useStationCall } from "./api.ts";
import { useDoing } from "./doing.ts";
import { t } from "./i18n.ts";
import { setPrefs, usePrefs } from "./prefs.ts";
import { useAct } from "@stillfail/ui/toast.tsx";

export type ArchiveHint = "off" | "done" | "reviewed";
export const HINTS: ArchiveHint[] = ["off", "done", "reviewed"];

/** The hint as kept on this device (none: done, the default), and how to change it. */
export function useArchiveHint(): [ArchiveHint, (hint: ArchiveHint) => void] {
  const kept = usePrefs((p) => p.archiveHint);
  const hint: ArchiveHint = kept === "off" || kept === "reviewed" ? kept : "done";
  return [hint, (v) => setPrefs({ archiveHint: v === "done" ? null : v })];
}

export const hintLabel = (h: ArchiveHint) => t(`web-pages.appearance.archive.${h}`);
export const hintNote = (h: ArchiveHint) => t(`web-pages.appearance.archive.${h}Hint`);

/** How a station archives on its own: never (no days), once idle, or once idle and recommended by its review. */
export type ArchiveMode = "off" | "idle" | "reviewed";
export const MODES: ArchiveMode[] = ["off", "idle", "reviewed"];
export const modeOf = (v: ArchivingView): ArchiveMode => (v.days <= 0 ? "off" : v.reviewed ? "reviewed" : "idle");
export const modeLabel = (m: ArchiveMode) => t(`web-pages.archiving.mode.${m}`);
export const modeNote = (m: ArchiveMode) => t(`web-pages.archiving.mode.${m}Hint`);

/** The days offered, with the one kept when it is none of them. */
export function daysOffered(kept: number, base: number[]): number[] {
  return kept > 0 && !base.includes(kept) ? [...base, kept].sort((a, b) => a - b) : base;
}
export const IDLE_DAYS = [1, 3, 7, 30];
export const SLACK_DAYS = [0, 3, 7, 30];
export const daysLabel = (n: number) => (n <= 0 ? t("web-pages.archiving.never") : t("web-pages.archiving.days", { n }));

/** What a station's row says of its archive review, and whether it is on. */
export function reviewOf(s: StationView): { on: boolean; text: string } {
  const rule = s.overview?.automaticDecisions?.settings.completion;
  const on = rule?.enabled === true;
  const model = s.overview?.automaticDecisions?.models.find((m) => m.id === rule?.model)?.name ?? rule?.model ?? "";
  return { on, text: on ? t("web-pages.archiving.reviewOn", { model }) : t("web-pages.archiving.reviewOff") };
}

/** A station's automatic archiving changed: the whole of it sent, as the station takes it. */
export function useArchivingSave(station: string): { save: (v: ArchivingView, patch: Partial<Pick<ArchivingView, "days" | "slackDays" | "reviewed">>) => void; busy: boolean } {
  const api = stationApi(useStationCall(station));
  const act = useAct();
  const busy = useDoing("archiving.save", { station });
  return {
    busy,
    save: (v, patch) => act(api.saveArchiving({ days: v.days, slackDays: v.slackDays, reviewed: v.reviewed, ...patch }), t("web-pages.archiving.saveWhat"), t("web-pages.archiving.saved")),
  };
}

/** The mode chosen: off forgets the days; idle or reviewed keeps those kept, or one. */
export function modePatch(v: ArchivingView, mode: ArchiveMode): Partial<Pick<ArchivingView, "days" | "reviewed">> {
  if (mode === "off") return { days: 0 };
  return { days: v.days > 0 ? v.days : 1, reviewed: mode === "reviewed" };
}
