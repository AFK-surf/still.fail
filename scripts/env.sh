# Source on Studio: toolchain paths for this session (elsewhere, e.g. on
# Windows or CI, the toolchain on PATH is used as is).
TOOLS=/Users/zuozijian/.stillfail/remote/sessions/df5e90815f47b3e730078057bed8feea81b11db927ea4ae88c9346fdc9260bb1/work/tools
if [ -d "$TOOLS" ]; then
  export MOON_HOME=$TOOLS/moon
  export PATH=$MOON_HOME/bin:$TOOLS/go/bin:$HOME/.local/bin:$PATH
fi
