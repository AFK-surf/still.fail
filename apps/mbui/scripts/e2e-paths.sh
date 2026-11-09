#!/bin/sh
# The local core and its recorder must agree on both defaults as well as explicitly supplied paths.
e2e_paths() {
  E2E_WORK="${E2E_WORK:-$(cd "$1/.." && pwd)/e2e-local}"
  E2E_STATION="${E2E_STATION:-${2:-/tmp/mbui-e2e-$(id -u)}}"
  export E2E_WORK E2E_STATION
}
