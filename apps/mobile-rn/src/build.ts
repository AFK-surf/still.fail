// What this build of the app is: where still.fail cloud is, and whether it is the beta app.
/**
 * still.fail cloud's origin: EXPO_PUBLIC_STILLFAIL_CLOUD when the build (or the bundler) is given one, a dev cloud's
 * for one (cloud/test/dev.ts, http://10.0.2.2:<port> from the emulator); else still.fail's own.
 */
export const CLOUD_ORIGIN = process.env.EXPO_PUBLIC_STILLFAIL_CLOUD || "https://app.still.fail";
export const BETA = false;
/** Where still.fail cloud's sign-in comes back to (cloud/src/auth.ts APP_REDIRECTS): ember://, which this app takes. */
export const AUTH_REDIRECT = "ember://auth/callback";
/** The app's name as people see it (the beta app's is youdid.wtf). */
export const APP_NAME = BETA ? "youdid.wtf" : "still.fail";
