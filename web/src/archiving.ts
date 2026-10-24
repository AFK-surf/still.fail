// 设置 › 归档, as the wide screen's page and the phone's screen show it alike: whether a done chat suggests archiving
// it (this device's `archiveHint`), and how each station archives chats on its own (its `archiving`, its managers'),
// beside whether its archive review is on (自动决策).
import type { ArchivingView, SettingsView } from "./core/shapes.ts";
import { useTopic } from "./core/react.ts";
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

/** How a station archives on its own and what each way to choose saves, its review and what the hint 按模型判断 means
 *  for the stations' reviews: the core's (present.ts archiving, the `settings` view). */
export function useSettingsView(workspace: string): SettingsView | undefined {
  return useTopic<SettingsView>({ topic: "settings", scope: workspace }).value;
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
