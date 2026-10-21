// The same numbers on every machine: sin, cos, exp, ln, pow and the rest worked out in MoonBit itself (MoonBit core's
// own ports of FreeBSD's msun / musl, its non-JS implementations: the files beside this one, their copyright kept),
// on every target. On js, @math's are the engine's Math.sin, Math.exp…: ECMAScript leaves their last bits to the
// engine, and an arm64 Mac's V8 and an x86 Linux's differ there; a picture or a motion worked out from them is not the
// same on two machines (still.fail's waiting pages' spinners, 2026-10-21). What a frame draws or a motion's value is
// made of takes these (detlint engine-math); sqrt, floor and the four operations are IEEE's own and the same anywhere.
