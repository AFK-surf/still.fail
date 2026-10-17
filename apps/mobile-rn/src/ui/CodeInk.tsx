// A code block's code, drawn (the Android app's ui/CodeInk.kt): plain first, with its final size, then coloured
// (Highlight.tsx), the colours changing only the ink, never the glyphs' metrics or the scrolling.
import { useEffect, useMemo, useState } from "react";
import { Text } from "react-native";
import { t } from "../i18n";
import { AnnotatedString, AnnotatedText } from "./Annotated";
import { highlight } from "./Highlight";
import { CodeWeight, webSubtle } from "./Markdown";
import { CODE_FONT, useC } from "./Theme";

/**
 * Coloured code kept by its key. Bound by source characters (not entry count), so a few large replies cannot keep
 * unlimited runs alive. Each component also holds its current one.
 */
const LIMIT = 128 * 1024;
const codeLayouts = new Map<string, { code: string; colored: AnnotatedString }>();
let codeChars = 0;
function cached(key: string): AnnotatedString | undefined {
  const hit = codeLayouts.get(key);
  if (!hit) return undefined;
  codeLayouts.delete(key);
  codeLayouts.set(key, hit);
  return hit.colored;
}
function keep(key: string, code: string, colored: AnnotatedString) {
  if (codeLayouts.has(key)) return;
  codeLayouts.set(key, { code, colored });
  codeChars += Math.max(1, code.length);
  for (const [k, v] of codeLayouts) {
    if (codeChars <= LIMIT) break;
    codeLayouts.delete(k);
    codeChars -= Math.max(1, v.code.length);
  }
}

/** Code up to this long (characters) is drawn plain as it is first drawn; longer, never. */
const SHAPED_AT_ONCE = 4_000;

interface Prepared { key: string; text: AnnotatedString; colored: boolean }

/**
 * Code is only drawn here. Colouring thousands of spans is not done as the block is first drawn: a frame later, so the
 * block is there at once. (Compose shapes off the UI thread, two at a time; here the words are laid out off the JS
 * thread by React Native itself, and the tokenizing, which is JS, waits for the frame after.)
 */
export function CodeInk({ code, language, dark }: { code: string; language: string | null | undefined; dark: boolean }) {
  const C = useC();
  const lang = language?.toLowerCase() ?? null;
  const key = `${dark ? 1 : 0}\u0000${lang ?? ""}\u0000${code}`;
  const first = useMemo<Prepared | null>(() => {
    const colored = cached(key);
    if (colored) return { key, text: colored, colored: true };
    // A little code is drawn plain at once, so its message has its height as it is first drawn, not "laying out"
    // and then taller; its colours come after.
    return code.length <= SHAPED_AT_ONCE ? { key, text: new AnnotatedString(code), colored: false } : null;
  }, [key]);
  const [prepared, setPrepared] = useState<Prepared | null>(first);
  useEffect(() => {
    setPrepared(first);
    if (first?.colored) return;
    let live = true;
    const timers: ReturnType<typeof setTimeout>[] = [];
    // Plain code first, with its final dimensions.
    if (first == null) timers.push(setTimeout(() => { if (live) setPrepared({ key, text: new AnnotatedString(code), colored: false }); }, 0));
    timers.push(setTimeout(() => {
      if (!live) return;
      const colored = highlight(code, lang, dark);
      keep(key, code, colored);
      setPrepared({ key, text: colored, colored: true });
    }, 0));
    return () => { live = false; timers.forEach(clearTimeout); };
  }, [key]);
  const result = prepared?.key === key ? prepared.text : first?.text;
  if (result == null) {
    // Nothing drawn till it is ready: even a plain 20 MB string is not safe to lay out at once.
    return <Text style={{ fontSize: 12.5, lineHeight: 20, height: 20, color: webSubtle(C), includeFontPadding: false }}>{t("android-misc.markdown.laying")}</Text>;
  }
  return (
    <AnnotatedText
      text={result}
      accessible
      accessibilityLabel={code}
      style={{ color: C.ink, fontFamily: CODE_FONT, fontWeight: CodeWeight, fontSize: 12.5, lineHeight: 20 }}
    />
  );
}
