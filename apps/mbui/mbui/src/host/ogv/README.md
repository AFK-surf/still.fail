# Offline Ogg and WebM decoder

These are the single-threaded WebAssembly files from the `ogv` 1.9.0 npm release
(<https://github.com/bvibber/ogv.js/tree/1.9.0>), except for the AV1 decoder
described below. The Mac player uses them when the system cannot decode a WebM
or when it opens Ogg video. They run in an isolated WebKit view and read the
file through the app, without a network URL. The accompanying COPYING, LICENSE
and PATENTS files are the notices shipped with that release.

The AV1 decoder uses the newer dav1d 1.5.2: the older decoder could fail on
ordinary 8-bit AV1 files. It is built from ogv.js commit
`3e7cbd3d0b0274b11191cb2e1bed0186f8661f84`, whose dav1d submodule is
`c720f4d3556a01916324aea155555d3efba842e8`. `DAV1D-COPYING` is its license.
To rebuild, check out those revisions, apply `git apply --unidiff-zero av1-build.patch`, and run
`buildscripts/compileDav1dWasm.sh` and `buildscripts/compileOgvDecoderVideoAV1.sh`
with Emscripten 6.0.1, Meson 1.12.1 and Ninja 1.13.2. Copy the resulting
`build/ogv-decoder-video-av1-wasm.js` and `.wasm` here. The patch disables SIMD
and threads for compatibility with older WebKit, builds both bit depths, and
reduces 10/12-bit 4:2:0 frames to the player's 8-bit output. It does not perform
HDR tone mapping.
