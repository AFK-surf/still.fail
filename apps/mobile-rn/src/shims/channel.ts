// web/src/channel.ts for the app: which channel this build is (still.fail, or the beta youdid.wtf).
import { BETA as APP_BETA } from "../build";

export const BETA_META = null;
export const BETA = APP_BETA;
export const NAME = BETA ? "youdid.wtf" : "still.fail";
