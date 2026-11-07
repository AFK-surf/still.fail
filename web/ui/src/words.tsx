// How the shared parts draw words the app wrote (a toast, a wait's line): the app may draw some of them its own way
// (its stations' marks by their names), given here; plain words otherwise.
import { createContext, type ComponentType } from "preact/compat";

export type WordsDrawn = ComponentType<{ text: string }>;

const Plain: WordsDrawn = ({ text }) => text;

export const Words = createContext<WordsDrawn>(Plain);
