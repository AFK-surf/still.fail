// The chats' files the core downloaded (chatDownloads.ts), saved: each all here taken once, whatever page shows, read
// as the core keeps it on the device and handed to the browser to save. The signed-in app's (CloudApp.tsx), not the
// preview's: the share page shows previews and has no core.
import { useEffect, useRef } from "react";
import { core, useCall, useTopic } from "./core/react.ts";
import type { DownloadsView } from "./core/shapes.ts";
import { stationCall } from "./api.ts";
import { failure, useToast } from "@stillfail/ui/toast.tsx";
import { t } from "./i18n.ts";
import { DOWNLOADS, saveBlob } from "./chatDownloads.ts";

/** Mounted once while signed in: each download all here taken (once) and saved. */
export function useDownloadsSaved(): void {
  const call = useCall();
  const toast = useToast();
  const list = useTopic<DownloadsView>(DOWNLOADS).value?.downloads;
  const taking = useRef(new Set<string>());
  useEffect(() => {
    // One taken is not taken again while the list still has it ready (the core's word that it is gone comes a turn
    // later); once it is out of the list it is forgotten, so the same file downloaded again is taken again.
    const ready = new Set((list ?? []).filter((d) => d.state === "ready").map((d) => d.id));
    for (const id of taking.current) if (!ready.has(id)) taking.current.delete(id);
    for (const d of list ?? []) {
      if (d.state !== "ready" || taking.current.has(d.id)) continue;
      taking.current.add(d.id);
      void (async () => {
        let taken: boolean;
        try {
          taken = (await core().call("download.take", { id: d.id }) as { taken: boolean }).taken;
        } catch {
          // (asked again as the list next changes)
          taking.current.delete(d.id);
          return;
        }
        // (taken by another page: out of the list by the next turn)
        if (!taken) return;
        const blob = await stationCall(call, d.station).file(d.key, d.name, false, undefined, d.size, true);
        const url = URL.createObjectURL(blob);
        saveBlob(url, d.name);
        setTimeout(() => URL.revokeObjectURL(url), 60_000);
      })().catch((e: unknown) => toast(t("web-main.preview.loadFailed", { error: failure(e) })));
    }
  }, [list, call, toast]);
}
