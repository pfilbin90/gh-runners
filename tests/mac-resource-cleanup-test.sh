#!/usr/bin/env bash
set -euo pipefail

scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

mkdir -p "$test_root/bin" "$test_root/home/.gradle" \
  "$test_root/home/Library/Developer/Xcode/DerivedData" \
  "$test_root/home/Library/Logs" "$test_root/runner/_diag"

cat >"$test_root/bin/gh" <<'SH'
#!/usr/bin/env bash
echo false
SH
cat >"$test_root/bin/lsof" <<'SH'
#!/usr/bin/env bash
exit 1
SH
chmod +x "$test_root/bin/gh" "$test_root/bin/lsof"

# Freshly downloaded packages may contain files with old upstream timestamps.
# Both payload and package-manager metadata must survive routine host cleanup.
package_files=(
  "Library/Caches/CocoaPods/Pods/Release/Example/1.0/XCFrameworks/Example.xcframework/Info.plist"
  "Library/Caches/CocoaPods/Pods/Specs/Release/Example/1.0.podspec.json"
  ".pub-cache/hosted/pub.dev/example-1.0/lib/example.dart"
  ".pub-cache/hosted-hashes/pub.dev/example-1.0.sha256"
)
for relative_path in "${package_files[@]}"; do
  file="$test_root/home/$relative_path"
  mkdir -p "$(dirname "$file")"
  printf 'package content\n' >"$file"
  touch -t 200001010000 "$file"
done
touch -t 200001010000 "$test_root/runner/_diag/old.log"
touch "$test_root/runner/_diag/recent.log"
analysis_cache="$test_root/home/.dartServer/.analysis-driver/00"
mkdir -p "$analysis_cache"
touch -t 200001010000 "$analysis_cache/old.resolved2"
touch "$analysis_cache/recent.resolved2"

PATH="$test_root/bin:$PATH" GH_BIN="$test_root/bin/gh" \
  GH_OWNER=test RUNNER_NAMES=test-mac RUNNER_HOME="$test_root/home" \
  RUNNER_DIRS="$test_root/runner" \
  bash "$scripts_dir/mac-resource-cleanup.sh"

for relative_path in "${package_files[@]}"; do
  file="$test_root/home/$relative_path"
  if [[ ! -f "$file" ]] || [[ "$(cat "$file")" != 'package content' ]]; then
    echo "Package cache file was removed or changed: $relative_path" >&2
    exit 1
  fi
done
[[ ! -e "$test_root/runner/_diag/old.log" ]]
[[ -f "$test_root/runner/_diag/recent.log" ]]
[[ ! -e "$analysis_cache/old.resolved2" ]]
[[ -f "$analysis_cache/recent.resolved2" ]]
echo "Host cleanup preserves package caches and still prunes old runner logs and Dart analyzer cache entries."
