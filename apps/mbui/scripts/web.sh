#!/bin/bash
# The browser build of this module's apps (APP=sffix by default): mbui's scripts/web.sh build | test.
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
export APP=${APP:-sffix}
exec bash "$MBUI_DIR/scripts/web.sh" "$@"
