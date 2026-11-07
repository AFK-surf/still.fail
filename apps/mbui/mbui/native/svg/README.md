# SVG renderer boundary

Pinned upstream resvg, called by `src/svgrender` on native, JS and both Wasm
targets. The application and device-frame renderer share this boundary.

The renderer returns a little-endian width/height header followed by straight
RGBA. The MoonBit owner caches immutable font buffers by identity, replaces the
database when they change and explicitly closes it when reset. Generic families
use parsed face zero and monospace uses parsed face one, matching the app.
External file references are disabled; embedded data images remain supported.

The C/Wasm ABI is private: buffers and databases must be created and released by
this module, exactly once. Input buffers are borrowed only for the call. The
returned raster allocation is released after copying into the caller's memory.
Native callers use `stub.c`; JS installs `loadSvg` before entering MoonBit; Wasm
imports are statically linked with this module so the existing runner can stay.
The native application compiles this source into its existing Rust shell.
Standalone tests and the web build use this crate.

Dependency licenses are retained upstream (resvg Apache-2.0 OR MIT, its dependencies under
their own licenses); this small wrapper is MIT like the repository.
