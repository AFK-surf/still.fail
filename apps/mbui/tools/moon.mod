name = "sftools"

version = "0.1.0"

source = "."

preferred_target = "native"

// Every warning an error but those after a `-` (apps/mbui/AGENTS.md, Warnings)
warnings = "@a"

import {
  "mbctools@0.1.0",
}
