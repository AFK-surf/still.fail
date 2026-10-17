// import.meta is the web code's (web/src/core/client.ts opens its worker with it, which this app never does): turned
// into what Hermes runs.
module.exports = function (api) {
  api.cache(true);
  return { presets: [["babel-preset-expo", { unstable_transformImportMeta: true }]] };
};
