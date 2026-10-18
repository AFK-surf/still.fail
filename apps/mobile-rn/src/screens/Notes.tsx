// Numbered notes, as a picture's marks have them (ImageMarks.tsx; web mobile/Notes.tsx): a pin with the number, the box
// a note is written in under what it is about, and the cards they gather into at the foot.
import { useEffect, useRef, useState } from "react";
import { Pressable, StyleSheet, TextInput, View, type StyleProp, type ViewStyle } from "react-native";
import Animated, { useAnimatedStyle, useSharedValue, withTiming } from "react-native-reanimated";
import { t } from "../i18n";
import { Floating } from "../ui/Glass";
import { Icons } from "../ui/Icon";
import { Ease } from "../ui/Motion";
import { IconIn, ripple } from "../ui/Parts";
import { Smooth } from "../ui/Smooth";
import { sp, T } from "../ui/Text";
import { raised, useC, withAlpha } from "../ui/Theme";

/** A numbered note, as its box and card show it (NoteBox, Card): a passage of a message's, or a mark on an image (ImageMarks.tsx). */
export interface NoteLike {
  readonly n: number;
  /** What it is about, in a line under what is said. */
  readonly text: string;
  comment: string;
  /** Its pin's colour (none: the accent). */
  readonly color?: string | null;
}

/** Where a pop grows from, as Compose's TransformOrigin (fractions of its width and height). */
export interface TransformOrigin { x: number; y: number }
const CENTER: TransformOrigin = { x: 0.5, y: 0.5 };

/** A note's number, as a web page's marks show theirs: a pin, its point at the bottom right. */
function Pin({ n, open = false, small = false, color = null, onClick = null }: { n: number; open?: boolean; small?: boolean; color?: string | null; onClick?: (() => void) | null }) {
  const C = useC();
  const size = small ? 16 : 20;
  const radii: [number, number, number, number] = small ? [8, 8, 2, 8] : [10, 10, 2, 10];
  // In the margin: pops in from its point, and grows a little while its note is open (160ms, as the web's).
  const grown = useSharedValue(open ? 1.12 : 1);
  useEffect(() => { grown.value = withTiming(open ? 1.12 : 1, { duration: 160, easing: Ease.Arrive }); }, [open, grown]);
  const popped = pop(160, { x: 1, y: 1 });
  const growing = useAnimatedStyle(() => ({ transform: [{ scale: grown.value }], transformOrigin: "100% 100%" }));
  // FontWeight(650) in Compose: React Native's weights go by hundreds, 600 the nearest.
  const pin = (
    <Smooth radius={radii} stroke={small ? undefined : { width: 2, color: "#FFFFFF" }} style={{ minHeight: size, minWidth: size, backgroundColor: color ?? C.accent, paddingHorizontal: 4, alignItems: "center", justifyContent: "center" }}>
      <T size={small ? 10 : 11} weight="600" line={16} color="#FFFFFF">{`${n}`}</T>
    </Smooth>
  );
  const body = onClick != null ? <Pressable onPress={onClick}>{pin}</Pressable> : pin;
  if (small) return body;
  return (
    <Animated.View style={popped}>
      <Animated.View style={growing}>{body}</Animated.View>
    </Animated.View>
  );
}

/** Saying something about a passage: a frosted composer floating under it, as the chat's is, the passage over what is written. */
export function NoteBox({ note, modifier, onDone, onRemove }: { note: NoteLike; modifier?: StyleProp<ViewStyle>; onDone: () => void; onRemove: () => void }) {
  const C = useC();
  const field = useRef<TextInput>(null);
  // What is written, drawn as it is typed; the note keeps it.
  const [comment, setComment] = useState(note.comment);
  // Focused at once: the keyboard comes up and the frame above the keyboard brings the box into view (Compose's
  // bringIntoView has no counterpart: what holds the box keeps it over the keyboard).
  useEffect(() => { field.current?.focus(); }, []);
  const popped = pop();
  return (
    <Animated.View style={[{ alignSelf: "stretch" }, modifier, popped]}>
      <Floating radius={26} tint={raised(C)} style={{ paddingLeft: 8, paddingRight: 8, paddingTop: 10, paddingBottom: 8, gap: 6 }}>
        <View style={{ flexDirection: "row", paddingHorizontal: 8, alignItems: "center", gap: 6 }}>
          <Pin n={note.n} small color={note.color ?? null} />
          <T size={13} line={18} color={C.muted} numberOfLines={1} ellipsizeMode="tail" style={{ flexShrink: 1 }}>{note.text}</T>
        </View>
        <View style={{ flexDirection: "row", alignItems: "flex-end", gap: 2 }}>
          <Pressable accessibilityLabel={t("android-chat.annotate.remove")} onPress={onRemove} android_ripple={ripple(C.ink)} style={{ width: 36, height: 36, borderRadius: 18, overflow: "hidden", alignItems: "center", justifyContent: "center" }}>
            <IconIn icon={Icons.Trash} size={17} tint={C.muted} />
          </Pressable>
          <View style={{ flex: 1, minWidth: 0, minHeight: 36, paddingHorizontal: 8, paddingVertical: 7, justifyContent: "center" }}>
            <TextInput
              ref={field}
              value={comment}
              onChangeText={(it) => { setComment(it); note.comment = it; }}
              placeholder={t("android-chat.annotate.write")}
              placeholderTextColor={C.subtle}
              multiline
              cursorColor={C.accent}
              selectionColor={withAlpha(C.accent, 0.4)}
              style={{ fontSize: sp(16), lineHeight: 21, color: C.ink, padding: 0, includeFontPadding: false, maxHeight: 21 * 8 }}
            />
          </View>
          <Pressable accessibilityLabel={t("android-chat.annotate.done")} onPress={onDone} android_ripple={ripple(C.bg)} style={{ width: 36, height: 36, borderRadius: 18, overflow: "hidden", backgroundColor: C.ink, alignItems: "center", justifyContent: "center" }}>
            <IconIn icon={Icons.Check} size={18} tint={C.bg} />
          </Pressable>
        </View>
      </Floating>
    </Animated.View>
  );
}

/** A note in the tray at the foot: its number and what is said, over the passage. `haze`: what the glass frosts (Haze's state; the blur here frosts what is behind by itself). */
export function Card({ note, open, haze: _haze, modifier, onClick }: { note: NoteLike; open: boolean; haze?: unknown; modifier?: StyleProp<ViewStyle>; onClick: () => void }) {
  const C = useC();
  const popped = pop();
  return (
    <Animated.View style={[{ width: 160 }, modifier, popped]}>
      <Floating radius={16}>
        <Pressable onPress={onClick} android_ripple={ripple(C.ink)} style={{ paddingHorizontal: 12, paddingVertical: 9 }}>
          <CardContent note={note} padded={false} />
        </Pressable>
        {/* Its note open: the accent's line round it. */}
        {open && <Smooth radius={16} stroke={{ width: 1.5, color: C.accent }} pointerEvents="none" style={StyleSheet.absoluteFill} />}
      </Floating>
    </Animated.View>
  );
}

/** What a note's card holds: its number and what is said, over the passage. */
function CardContent({ note, padded = true }: { note: NoteLike; padded?: boolean }) {
  const C = useC();
  const said = note.comment.trim();
  return (
    <View style={[{ gap: 3 }, padded && { paddingHorizontal: 12, paddingVertical: 9 }]}>
      <View style={{ flexDirection: "row", alignItems: "center", gap: 6 }}>
        <Pin n={note.n} small color={note.color ?? null} />
        <T size={14} line={20} color={said === "" ? C.muted : C.ink} numberOfLines={1} ellipsizeMode="tail" style={{ flexShrink: 1 }}>{said || t("android-chat.annotate.quoteOnly")}</T>
      </View>
      <T size={12} line={17} color={C.muted} numberOfLines={1} ellipsizeMode="tail">{note.text}</T>
    </View>
  );
}

/**
 * Coming in as the web's pop does (keyframes.css.ts popKeyframes over --m-ease): from nothing and 97% of its size to
 * itself, `ms` long, from `origin` (its middle by default). A hook: the animated style to put on what comes in.
 */
export function pop(ms = 140, origin: TransformOrigin = CENTER) {
  const p = useSharedValue(0);
  useEffect(() => { p.value = withTiming(1, { duration: ms, easing: Ease.Arrive }); }, [p, ms]);
  const at = `${origin.x * 100}% ${origin.y * 100}%`;
  return useAnimatedStyle(() => {
    const s = 0.97 + 0.03 * p.value;
    return { opacity: p.value, transform: [{ scale: s }], transformOrigin: at };
  });
}
