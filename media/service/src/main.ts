// The media service as the station starts it (its module `media`, docs/media-service.md): where its data is, the socket
// it answers on, and the station's local API, all from the environment. Stops cleanly on SIGTERM (and SIGINT).
import { startService } from "./server.ts";

const need = (name: string): string => {
  const v = process.env[name];
  if (!v) {
    console.error(`media: ${name} is not set (the station starts this service as a module)`);
    process.exit(2);
  }
  return v;
};

const id = process.env.STILLFAIL_MODULE_ID ?? "media";
const service = await startService({
  dir: need("STILLFAIL_MODULE_DIR"),
  socket: need("STILLFAIL_MODULE_SOCKET"),
  station: { socket: need("STILLFAIL_STATION_SOCKET"), token: need("STILLFAIL_STATION_TOKEN") },
});
console.error(`media: module ${id} listening on ${process.env.STILLFAIL_MODULE_SOCKET}`);

const stop = (signal: string) => {
  console.error(`media: ${signal}, stopping`);
  /// Gone in 5 s even if a request does not end.
  setTimeout(() => process.exit(0), 5_000).unref();
  service.close().then(
    () => process.exit(0),
    (e) => {
      console.error("media: stopping failed", e);
      process.exit(1);
    },
  );
};
process.once("SIGTERM", () => stop("SIGTERM"));
process.once("SIGINT", () => stop("SIGINT"));
