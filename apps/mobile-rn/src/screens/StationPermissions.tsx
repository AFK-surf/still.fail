// A Mac station's grants to still.fail Helper (the overview's `permissions`, as the core says them: docs/remote-screens.md
// "Grants") on its page, as the phone web's (web/src/StationPermissions.tsx): a row each with what it is for and whether
// it is given; one not given asked for from here (`permissions.request`), which puts the helper's window up on that Mac.
// Where the Mac's screen can be seen and driven the next step is that screen, opened at once, for the person to click in
// the window from wherever they are; else the row says to click Allow on that Mac, and turns as they do. A station that
// says none (not a Mac, or older) shows nothing.
import { Pressable, View, type TextStyle } from "react-native";
import type { StationGrant, StationPermissions } from "../../../../web/src/core/shapes.ts";
import { useDoing, useDoingFailed } from "../../../../web/src/doing.ts";
import { app } from "../AppState";
import { t } from "../i18n";
import { DoingMark } from "../ui/Controls";
import { Icon, Icons } from "../ui/Icon";
import type { IconPaths } from "../ui/IconSet";
import { ListCard, ListRow, SectionHeader } from "../ui/Parts";
import { T } from "../ui/Text";
import { useC, withAlpha } from "../ui/Theme";

/** Each grant's mark (as the web's GRANT_MARK): the screen's two by what they do, the folders by what they hold. */
function grantMark(id: string): IconPaths {
  switch (id) {
    case "capture": return Icons.Monitor;
    case "control": return Icons.Cursor;
    case "documents": return Icons.FileText;
    case "downloads": return Icons.Download;
    case "removable": return Icons.Disk;
    case "network": return Icons.Server;
    default: return Icons.Folder;
  }
}

/** What a row does at its end (the web's grantEnd): say it is given, open the screen (its window up, the screen drivable), wait for it at the Mac, ask for it, or (a member who may not ask) say it is not given. */
type GrantEnd = "Granted" | "Open" | "Waiting" | "Request" | "Missing";

function grantEnd(g: StationGrant, p: StationPermissions): GrantEnd {
  if (g.granted) return "Granted";
  if (g.asking) return p.screen != null ? "Open" : "Waiting";
  if (p.canRequest) return "Request";
  return "Missing";
}

/** The station page's section (Stations.tsx StationScreen), under its screens; `name`: the station's, the screen viewer's title. */
export function StationPermissionsSection({ address, name, p }: { address: string; name: string; p: StationPermissions }) {
  const C = useC();
  const open = () => app.openScreen(address, "desktop", name);
  return (
    <>
      <SectionHeader title={t("android-misc.permissions.section")} start={24} />
      <ListCard>
        {p.grants.map((g) => <GrantRow key={g.id} address={address} g={g} end={grantEnd(g, p)} open={open} />)}
      </ListCard>
      {/* What is unavailable now for want of a grant. */}
      {p.note != null && <T size={13} line={18} color={C.muted} style={{ paddingHorizontal: 24, paddingBottom: 10 }}>{p.note}</T>}
    </>
  );
}

function GrantRow({ address, g, end, open }: { address: string; g: StationGrant; end: GrantEnd; open: () => void }) {
  const C = useC();
  const on = { station: address, grant: g.id };
  const busy = useDoing("permissions.request", on);
  const failed = useDoingFailed("permissions.request", on);
  return (
    <ListRow>
      <Icon icon={grantMark(g.id)} size={18} color={C.muted} />
      <View style={{ flex: 1, minWidth: 0 }}>
        <T size={15} line={20} color={C.ink} numberOfLines={1}>{g.name}</T>
        {/* While its window is up, how it is given there. */}
        <T size={13} line={18} color={g.asking ? C.ink : C.muted} numberOfLines={2}>{g.line}</T>
      </View>
      {end === "Granted" && <EndWords text={t("android-misc.permissions.granted")} color={C.muted} />}
      {end === "Waiting" && <EndWords text={t("android-misc.permissions.waiting")} color={C.muted} />}
      {end === "Missing" && <EndWords text={t("android-misc.permissions.missing")} color={C.warn} weight="500" />}
      {end === "Open" && <RowAction label={t("android-misc.permissions.openScreen")} onClick={open} />}
      {end === "Request" && (
        <RowAction
          label={t("android-misc.permissions.request")}
          description={t("android-misc.permissions.requestLabel", { name: g.name })}
          busy={busy}
          failed={failed}
          onClick={() => {
            // One tap: the window up on the Mac, then its screen here to click in it, where it can be driven.
            app.act(t("android-misc.permissions.requestWhat", { name: g.name }), async () => { if (await app.api(address).requestGrant(g.id)) open(); });
          }}
        />
      )}
    </ListRow>
  );
}

/** A row's state at its end, in words. */
function EndWords({ text, color, weight = "400" }: { text: string; color: string; weight?: TextStyle["fontWeight"] }) {
  return <T size={13} line={18} weight={weight} color={color} numberOfLines={1} ellipsizeMode="clip">{text}</T>;
}

/**
 * What may be done, at a row's end, in the accent (as the station's versions' rows, Versions.tsx, and the phone web's):
 * a spinner before it while `busy` (not pressed again), the mark of a failure a moment after (DoingMark). Its press
 * reaches above and below the words.
 */
function RowAction({ label, description, busy = false, failed, onClick }: { label: string; description?: string; busy?: boolean; failed?: string; onClick: () => void }) {
  const C = useC();
  return (
    <Pressable
      disabled={busy}
      onPress={onClick}
      accessibilityRole="button"
      accessibilityLabel={description}
      android_ripple={{ color: withAlpha(C.ink, 0.1) }}
      style={{ paddingVertical: 8, flexDirection: "row", alignItems: "center", gap: 6 }}
    >
      {(busy || failed != null) && <DoingMark running={busy} failed={failed ?? null} inline />}
      <T size={13} line={18} weight="500" color={busy ? C.muted : C.accent} numberOfLines={1} ellipsizeMode="clip">{label}</T>
    </Pressable>
  );
}
