// An agent's words with its files (web/src/Chat.tsx → ProseWithFiles, PlacedFile, FileLink): those its text names
// are drawn where it names them (an HTML one as its visualization, an image whole, several images of one paragraph
// side by side), the rest below it, as they always were.
import { useMemo, useState } from "react";
import { Modal, Pressable, View, type StyleProp, type ViewStyle } from "react-native";
import type { Attachment } from "../../../../web/src/core/shapes.ts";
import { Markdown, Placing } from "../ui/Markdown";
import { LocalFollowUp } from "../ui/Viz";
import type { Here } from "./Chat";
import { FileCard, Files, StationImage } from "./ChatFiles";
import type { Draft } from "./Composer";
import { FilePreview } from "./FilePreview";
import { VizFile, VizOpen } from "./VizFiles";

const IMAGE = /\.(png|jpe?g|gif|webp)$/i;
const HTML = /\.html?$/i;

/**
 * An agent's Markdown with its files: those its text names (`placed`, by name: the core decides which) shown there, the
 * rest below it. `draft`: where words a visualization asks to send go (the composer), for the person to send.
 */
export function AgentWords({ ctx, text, files, names, draft = null }: { ctx: Here; text: string; files: Attachment[]; names: string[]; draft?: Draft | null }) {
  const [placed, rest] = useMemo(() => {
    const placed = new Map<string, Attachment>();
    for (const n of names) {
      const f = files.find((it) => it.name === n);
      if (f) placed.set(n, f);
    }
    const values = [...placed.values()];
    return [placed, files.filter((f) => !values.includes(f))] as const;
  }, [files, names]);
  const [opened, setOpened] = useState<Attachment | null>(null);
  const placing = placed.size === 0 ? null : new Placing(
    placed,
    (f: Attachment) => <PlacedFile ctx={ctx} file={f} />,
    (f: Attachment, size: StyleProp<ViewStyle>) => {
      const owner = ctx.owner(f);
      if (owner != null && IMAGE.test(f.name)) return <StationImage station={ctx.station} sessionKey={owner} file={f} modifier={size} gallery={ctx.of} />;
      // Markdown's ![] can place a video (or any file), too. Its card must open the same preview as a link.
      return <FileCard name={f.name} size={f.size} onClick={owner != null ? () => setOpened(f) : null} />;
    },
    (f: Attachment) => setOpened(f),
  );
  const followUp = draft
    ? (words: string) => {
        draft.text = draft.text.trim().length === 0 ? words : `${draft.text.trimEnd()}\n${words}`;
        draft.focus++;
        return true;
      }
    : null;
  return (
    <View>
      <LocalFollowUp.Provider value={followUp}>
        <Markdown text={text} placing={placing} />
      </LocalFollowUp.Provider>
      {rest.length > 0 && <View style={{ paddingTop: 4 }}><Files ctx={ctx} list={rest} /></View>}
      {opened && <OpenedFile ctx={ctx} file={opened} onClose={() => setOpened(null)} />}
    </View>
  );
}

/**
 * A file the text places on a line of its own: an HTML one is a visualization, drawn there (how agents make one is
 * the stillfail-viz skill); any other shows as below the text.
 */
function PlacedFile({ ctx, file }: { ctx: Here; file: Attachment }) {
  const owner = ctx.owner(file);
  if (owner != null && HTML.test(file.name)) return <VizFile station={ctx.station} sessionKey={owner} file={file} failed={() => <FileCard name={file.name} size={file.size} />} />;
  return <Files ctx={ctx} list={[file]} />;
}

/** A file a link within a sentence names, opened: a visualization over the whole screen; any other as its message shows it, over the page. */
function OpenedFile({ ctx, file, onClose }: { ctx: Here; file: Attachment; onClose: () => void }) {
  const owner = ctx.owner(file);
  if (owner != null && HTML.test(file.name)) return <VizOpen station={ctx.station} sessionKey={owner} file={file} onClose={onClose} />;
  // Any other opens in the file preview (FilePreview.tsx), as a tap on it below the text does.
  if (owner != null) return <FilePreview station={ctx.station} sessionKey={owner} file={file} gallery={{ kind: "Chat", of: ctx.of }} onClose={onClose} />;
  return (
    <Modal transparent visible onRequestClose={onClose} statusBarTranslucent navigationBarTranslucent>
      <Pressable onPress={onClose} style={{ flex: 1, backgroundColor: "#00000080", alignItems: "center", justifyContent: "center" }}>
        <Files ctx={ctx} list={[file]} />
      </Pressable>
    </Modal>
  );
}
