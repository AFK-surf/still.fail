// A scripted tour for screen recordings where no touches can be sent (the iOS simulator here): opened by the link
// stillfailrn:///?demo=1, it scrolls the list down and back, opens a chat and goes back, then visits another place.
import { router } from "expo-router";
import type { FlatList } from "react-native";

const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));

function glide(list: FlatList<unknown>, from: number, to: number, ms: number) {
  return new Promise<void>((done) => {
    const start = Date.now();
    const step = () => {
      const k = Math.min(1, (Date.now() - start) / ms);
      const e = k < 0.5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2;
      list.scrollToOffset({ offset: from + (to - from) * e, animated: false });
      if (k < 1) requestAnimationFrame(step);
      else done();
    };
    requestAnimationFrame(step);
  });
}

export async function tour(list: FlatList<unknown>) {
  await wait(800);
  await glide(list, 0, 1600, 1800);
  await wait(500);
  await glide(list, 1600, 0, 1200);
  await wait(600);
  router.push({ pathname: "/chat/[id]", params: { id: "1" } });
  await wait(1500);
  router.back();
  await wait(1000);
  router.navigate("/files");
  await wait(1000);
  router.navigate("/");
}
