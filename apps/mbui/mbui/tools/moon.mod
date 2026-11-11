name = "mbctools"

version = "0.1.0"

source = "."

preferred_target = "native"

// Every warning an error but those after a `-` (apps/mbui/AGENTS.md, Warnings). 27 is off till every machine's MoonBit
// knows `#derive(…)` before a type (0.1.20261104's ask of rjson's `derive(Eq)`; 0.1.20261016 takes it for an unknown
// attribute and derives nothing)
warnings = "@a-79-27"
