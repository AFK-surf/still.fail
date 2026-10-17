// The pages' small parts used across them (the chats', the drive's, the screens', the share sheet's): buttons, fields,
// rows to pick from, the mark of what was set going. Moved here from screens/ so that what is not a chat's page does not
// depend on the pages (2026-10-17).
import type { ReactNode } from "react";
import { Pressable, TextInput, View, type StyleProp, type ViewStyle } from "react-native";
import { Icons } from "./Icon";
import type { IconPaths } from "./IconSet";
import { useUi } from "./Host";
import { IconIn, ripple } from "./Parts";
import { Smooth } from "./Smooth";
import { T } from "./Text";
import { CODE_FONT, useC } from "./Theme";
import { BusyIcon, Spinner } from "./Waiting";

/**
 * Where what someone set going shows how it is (useDoing / useDoingFailed): a spinner while it is under way, a small
 * red mark the few seconds after it failed (a tap says why), nothing otherwise. The menu or sheet that asked may be gone.
 */
export function DoingMark({ running, failed, inline = false }: { running: boolean; failed: string | null | undefined; inline?: boolean }) {
  const C = useC();
  const ui = useUi();
  if (running) return <Spinner inline={inline} />;
  // The app only for what failed: a spinner shows where there is none (the share sheet over another app).
  if (failed != null) {
    return (
      <Pressable onPress={() => ui.note(failed)} accessibilityLabel={failed}>
        <IconIn icon={Icons.Info} size={inline ? 12 : 14} tint={C.red} />
      </Pressable>
    );
  }
  return null;
}

/**
 * A row of a picking sheet: what, a line under it, and a check on the chosen one; `busy`: what it set going is under way
 * (a spinner, not tapped again); `done`: what it stands for is done (a station joined: not tapped again, the line under it
 * and a check in green); `failed`: it failed a moment ago (DoingMark); `mark`: drawn before what (a station's icon);
 * `subLines`: at most that many lines of the line under it (a chat's last message: one).
 */
export function PickRow({ label, sub, checked = false, enabled = true, busy = false, done = false, failed, color, leading, mark, subLines, onClick }: {
  label: string; sub?: string | null; checked?: boolean; enabled?: boolean; busy?: boolean; done?: boolean; failed?: string | null; color?: string;
  leading?: (() => ReactNode) | null; mark?: (() => ReactNode) | null; subLines?: number; onClick: () => void;
}) {
  const C = useC();
  const ink = enabled ? (color ?? C.ink) : C.subtle;
  return (
    <View style={{ paddingHorizontal: 12 }}>
      <Pressable
        onPress={onClick}
        disabled={!(enabled && !busy && !done)}
        android_ripple={ripple(C.ink)}
        style={{ alignSelf: "stretch", flexDirection: "row", alignItems: "center", gap: 12, paddingHorizontal: 8, paddingVertical: 12 }}
      >
        {leading?.()}
        <View style={{ flex: 1, minWidth: 0 }}>
          {mark == null ? (
            <T size={15} color={ink}>{label}</T>
          ) : (
            <View style={{ flexDirection: "row", alignItems: "center", gap: 6 }}>
              {mark()}
              <T size={15} color={ink}>{label}</T>
            </View>
          )}
          {sub != null && <T size={12} color={done ? C.green : C.muted} numberOfLines={subLines} ellipsizeMode="tail">{sub}</T>}
        </View>
        {busy || failed != null
          ? <DoingMark running={busy} failed={failed} />
          : done
            ? <IconIn icon={Icons.Check} size={14} tint={C.green} />
            : checked && <IconIn icon={Icons.Check} size={14} tint={C.accent} />}
      </Pressable>
    </View>
  );
}

export function Button({ label, primary, busy = false, enabled = true, danger = false, onClick }: { label: string; primary: boolean; busy?: boolean; enabled?: boolean; danger?: boolean; onClick: () => void }) {
  const C = useC();
  const on = enabled && !busy;
  const ink = primary && danger && enabled ? "#FFFFFF" : primary ? C.bg : C.ink;
  const ground = primary ? (!enabled ? C.line : danger ? C.red : C.ink) : C.chip;
  return (
    <Smooth radius={19} style={{ height: 38, backgroundColor: ground }}>
      <Pressable
        onPress={onClick}
        disabled={!on}
        android_ripple={ripple(ink)}
        style={{ height: 38, flexDirection: "row", alignItems: "center", gap: 8, paddingHorizontal: 16 }}
      >
        {/* A solid one's spinner in its words' colour. */}
        <BusyIcon busy={busy} solid={primary ? ink : null} />
        <T size={14} weight="600" color={ink}>{label}</T>
      </Pressable>
    </Smooth>
  );
}

/** A line to type in, on a soft frame; `lines` above one: a few lines, of any length (a pasted list). */
export function Field({ value, onChange, placeholder, mono = false, modifier: modifier_, style = modifier_, lines = 1 }: { value: string; onChange: (v: string) => void; placeholder: string; mono?: boolean; modifier?: StyleProp<ViewStyle>; style?: StyleProp<ViewStyle>; lines?: number }) {
  const C = useC();
  const font = mono ? { fontFamily: CODE_FONT } : null;
  return (
    <Smooth radius={12} stroke={{ width: 1, color: C.line }} style={[style, { alignSelf: "stretch", backgroundColor: C.surface, paddingHorizontal: 12, paddingVertical: 10 }]}>
      {value.length === 0 && <T color={C.subtle} size={15} style={[{ position: "absolute", left: 12, top: 10 }, font]}>{placeholder}</T>}
      <TextInput
        value={value}
        onChangeText={(it) => onChange(lines > 1 ? it : it.slice(0, mono ? 32 : 80))}
        multiline={lines > 1}
        numberOfLines={lines > 1 ? lines : undefined}
        cursorColor={C.accent}
        selectionColor={C.accent}
        underlineColorAndroid="transparent"
        textAlignVertical="top"
        style={[{ color: C.ink, fontSize: 15, padding: 0, margin: 0, includeFontPadding: false }, lines > 1 && { minHeight: lines * 15 * 1.17 }, font]}
      />
    </Smooth>
  );
}

export function GroupLabel({ text }: { text: string }) {
  const C = useC();
  return <T size={13} color={C.muted} style={{ paddingTop: 14, paddingBottom: 4 }}>{text}</T>;
}

export function fileSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
  return `${(bytes / 1024 / 1024 / 1024).toFixed(2)} GB`;
}

/** The line icon an entry of the drive is drawn with, by its kind (the core's `kind`). */
export function kindIcon(kind: string): IconPaths {
  switch (kind) {
    case "folder": return Icons.Folder;
    case "video": return Icons.FileVideo;
    case "audio": return Icons.FileAudio;
    case "image": return Icons.Photo;
    case "markdown": case "text": case "subtitle": return Icons.FileText;
    case "code": case "csv": case "html": return Icons.FileCode;
    case "pdf": return Icons.FilePdf;
    default: return Icons.File;
  }
}

// Controls.kt's Context.activity() (the activity behind a Dialog's wrapped context, for the viewers' landscape button)
// has no counterpart here: React Native has one activity and no Dialog contexts; turning the screen is the orientation
// module's (wherever the viewers are ported), not a context's.
