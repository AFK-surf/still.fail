// How the shared parts draw words the app wrote (a toast, a wait's line): the app may draw some of them its own way
// (its stations' marks by their names, web/src/StationNamed.tsx), given here; plain words otherwise.
import { createContext, type ComponentType } from "react";

export type WordsDrawn = ComponentType<{ text: string }>;

const Plain: WordsDrawn = ({ text }) => text;

export const Words = createContext<WordsDrawn>(Plain);
