// The folders a station lends the workspaces it joined (docs/multi-workspace.md): picked by its home workspace's owners
// and admins, on its drive's folders, beside pinning one for its own. What each has now is the core's `memberships`.
import { useMemberships } from "../api.ts";
import { useAct } from "@stillfail/ui/toast.tsx";
import { Pin } from "@stillfail/ui/icons.tsx";
import type { MenuItem } from "../ui.tsx";
import { drive, folderName } from "./useDrive.ts";
import { t } from "../i18n.ts";

/**
 * For a station's managers, while it is in more than one workspace: a folder (an absolute path on it) lent to each
 * workspace it joined, or no longer, as items of the folder's menu; none for anyone else. `anywhere`: the viewer
 * browses every folder (a manager does), else nothing is asked.
 */
export function useJoinedPins(station: string, anywhere: boolean): (abs: string) => MenuItem[] {
  const m = useMemberships(anywhere ? station : null).value;
  const act = useAct();
  const joined = m?.manages ? m.workspaces.filter((w) => !w.home) : [];
  return (abs) => joined.map((w) => {
    const on = w.roots.some((r) => r.path === abs);
    return {
      label: t(on ? "web-pages.drive.unpinFor" : "web-pages.drive.pinFor", { name: w.name }), icon: Pin,
      onSelect: () => act(drive.pinFor(station, w.roots, abs, !on, w.workspace), t("web-pages.drive.rootsWhat"),
        t(on ? "web-pages.drive.unsharedWith" : "web-pages.drive.sharedWith", { folder: folderName(abs), name: w.name })),
    };
  });
}
