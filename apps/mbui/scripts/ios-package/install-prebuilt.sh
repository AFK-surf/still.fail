#!/bin/bash
# Called only by the generated Xcode targets; signing belongs entirely to Xcode.
set -euo pipefail
kind="${1:?expected app or share}"
case "$kind" in
  app) source_dir="$SRCROOT/staged/App" ;;
  share) source_dir="$SRCROOT/staged/Share" ;;
  *) echo "Unknown prebuilt payload: $kind" >&2; exit 1 ;;
esac
destination="$TARGET_BUILD_DIR/$WRAPPER_NAME"
mkdir -p "$destination"
# Remove only obsolete files previously copied by this payload phase. Keep the
# ownership inventory outside the signed bundle; never recursively delete Xcode outputs.
mkdir -p "${DERIVED_FILE_DIR:?Xcode must supply DERIVED_FILE_DIR}"
manifest="$DERIVED_FILE_DIR/mbui-payload-$kind.json"
next=$(mktemp "$DERIVED_FILE_DIR/mbui-payload-next.XXXXXX")
trap 'rm -f "$next"' EXIT
python3 - "$source_dir" "$destination" "$manifest" "$next" <<'PY_INVENTORY'
import fnmatch, json, os, pathlib, sys
source, destination, manifest, output = map(pathlib.Path, sys.argv[1:])
destination = destination.resolve()
def allowed(relative):
    parts = pathlib.PurePosixPath(relative).parts
    return bool(parts) and not pathlib.PurePosixPath(relative).is_absolute() and all(p not in (".", "..") for p in parts) and parts[0] not in ("Info.plist", "PkgInfo", "Frameworks", "PlugIns") and not any(p == "_CodeSignature" or fnmatch.fnmatch(p, "*.mobileprovision") or fnmatch.fnmatch(p, "*.provisionprofile") for p in parts)
current = set()
for root, dirs, files in os.walk(source, followlinks=False):
    for name in list(dirs):
        path = pathlib.Path(root) / name
        relative = path.relative_to(source).as_posix()
        if not allowed(relative):
            dirs.remove(name)
        elif path.is_symlink():
            current.add(relative)
            dirs.remove(name)
    for name in files:
        relative = (pathlib.Path(root) / name).relative_to(source).as_posix()
        if allowed(relative):
            current.add(relative)
previous = json.loads(manifest.read_text()) if manifest.exists() else {}
if previous.get("destination") == str(destination):
    for relative in set(previous.get("files", [])) - current:
        if not isinstance(relative, str) or not allowed(relative):
            raise SystemExit("Unsafe payload inventory entry")
        target = destination / relative
        if not target.parent.resolve().is_relative_to(destination):
            raise SystemExit("Payload inventory traverses symlink")
        if target.is_symlink() or target.is_file():
            target.unlink()
            parent = target.parent
            while parent != destination:
                try:
                    parent.rmdir()
                except OSError:
                    break
                parent = parent.parent
pathlib.Path(output).write_text(json.dumps({"destination": str(destination), "files": sorted(current)}))
PY_INVENTORY
# Never overwrite Xcode-owned metadata, embedded code, profiles or signatures.
/usr/bin/rsync -a \
  --exclude='/Info.plist' --exclude='/PkgInfo' --exclude='/Frameworks' --exclude='/PlugIns' \
  --exclude='_CodeSignature' --exclude='*.mobileprovision' \
  --exclude='*.provisionprofile' \
  "$source_dir/" "$destination/"
chmod +x "$destination/$EXECUTABLE_NAME"
if [ "$kind" = app ]; then
  test -s "$destination/core.hbc"
fi

mv -f "$next" "$manifest"
