#!/bin/bash

set -euo pipefail

# Package workflow/ into a distributable .alfredworkflow (a ZIP).
# Run from the repository root: ./build.sh

WORKFLOW_DIR="workflow"
DIST_DIR="dist"
BUILD_DIR="build_tmp"

if [[ ! -f "$WORKFLOW_DIR/info.plist" ]]; then
    echo "❌ $WORKFLOW_DIR/info.plist not found" >&2
    exit 1
fi

# Extract the version (plutil, with a grep/sed fallback for Linux CI).
if command -v plutil >/dev/null 2>&1; then
    VERSION=$(plutil -extract version raw "$WORKFLOW_DIR/info.plist" 2>/dev/null || echo "0.0.0")
else
    VERSION=$(grep -A1 '<key>version</key>' "$WORKFLOW_DIR/info.plist" \
        | grep '<string>' | sed 's/.*<string>\(.*\)<\/string>.*/\1/' || echo "0.0.0")
fi

OUTPUT_FILE="${DIST_DIR}/alfred-claude-cli-v${VERSION}.alfredworkflow"

echo "📦 Building Claude CLI workflow v${VERSION}"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"
cp -R "$WORKFLOW_DIR/"* "$BUILD_DIR/"

# Make scripts executable.
find "$BUILD_DIR/scripts" -type f -name "*.sh" -exec chmod +x {} \;

# Inject the readme Markdown (kept in a separate file) into info.plist.
README_SRC="$WORKFLOW_DIR/readme.md"
if [[ ! -f "$README_SRC" ]]; then
    echo "❌ $README_SRC not found" >&2
    rm -rf "$BUILD_DIR"
    exit 1
fi
if command -v plutil >/dev/null 2>&1; then
    plutil -replace readme -string "$(cat "$README_SRC")" "$BUILD_DIR/info.plist"
elif command -v python3 >/dev/null 2>&1; then
    python3 - "$BUILD_DIR/info.plist" "$README_SRC" <<'PY'
import plistlib, sys
plist_path, readme_path = sys.argv[1], sys.argv[2]
with open(plist_path, "rb") as f:
    data = plistlib.load(f)
with open(readme_path, "r") as f:
    data["readme"] = f.read().rstrip("\n")
with open(plist_path, "wb") as f:
    plistlib.dump(data, f)
PY
else
    echo "❌ Need plutil or python3 to inject the readme" >&2
    rm -rf "$BUILD_DIR"
    exit 1
fi
echo "📝 Injected readme from $README_SRC"

# Validate the workflow structure.
REQUIRED_FILES=(
    "$BUILD_DIR/info.plist"
    "$BUILD_DIR/scripts/passthrough.sh"
    "$BUILD_DIR/scripts/view.sh"
    "$BUILD_DIR/scripts/common.sh"
)
for file in "${REQUIRED_FILES[@]}"; do
    if [[ ! -f "$file" ]]; then
        echo "❌ Required file missing: ${file#$BUILD_DIR/}" >&2
        rm -rf "$BUILD_DIR"
        exit 1
    fi
done

# Zip the contents (not the parent dir) into the .alfredworkflow.
rm -f "$OUTPUT_FILE"
( cd "$BUILD_DIR" && zip -qr "../$OUTPUT_FILE" ./* -x "*.DS_Store" )
rm -rf "$BUILD_DIR"

echo "✅ Built $OUTPUT_FILE ($(du -h "$OUTPUT_FILE" | cut -f1))"
