#!/usr/bin/env bash
# Patch an existing standalone Node executable without changing npm or runner state.
# Run between jobs. Existing processes retain the old executable until they exit.
set -euo pipefail

version="${1:?Usage: patch-node-binary.sh VERSION /absolute/path/to/node}"
target="${2:?An existing Node executable is required}"
case "$version" in
  22.23.4|24.22.1) ;;
  *) echo "Unsupported security baseline: $version" >&2; exit 1 ;;
esac
[[ "$target" = /* && -f "$target" && ! -L "$target" ]] || {
  echo "Target must be an existing absolute, non-symlink executable path" >&2
  exit 1
}

# Never downgrade a newer patch, or silently change the executable's major version.
decision="$("$target" -e '
  const current = process.versions.node.split(".").map(Number);
  const required = process.argv[1].split(".").map(Number);
  if (current[0] !== required[0]) process.exit(1);
  console.log(current[1] > required[1] ||
    (current[1] === required[1] && current[2] >= required[2]) ? "current" : "patch");
' "$version")"
if [[ "$decision" = current ]]; then
  echo "$target already meets $version: $("$target" --version)"
  exit 0
fi

case "$(uname -s)" in
  Darwin) platform=darwin ;;
  Linux) platform=linux ;;
  *) echo "Unsupported OS" >&2; exit 1 ;;
esac
case "$(uname -m)" in
  arm64|aarch64) arch=arm64 ;;
  x86_64) arch=x64 ;;
  *) echo "Unsupported architecture" >&2; exit 1 ;;
esac

scratch="$(mktemp -d)"
staged=""
trap 'rm -rf "$scratch"; if [[ -n "$staged" ]]; then rm -f "$staged"; fi' EXIT
archive="node-v${version}-${platform}-${arch}.tar.gz"
base="https://nodejs.org/dist/v${version}"
curl --fail --silent --show-error --location --retry 3 --connect-timeout 15 --max-time 120 "$base/$archive" -o "$scratch/$archive"
curl --fail --silent --show-error --location --retry 3 --connect-timeout 15 --max-time 120 "$base/SHASUMS256.txt" -o "$scratch/SHASUMS256.txt"
expected="$(awk -v file="$archive" '$2 == file {print $1}' "$scratch/SHASUMS256.txt")"
if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "$scratch/$archive" | awk '{print $1}')"
else
  actual="$(shasum -a 256 "$scratch/$archive" | awk '{print $1}')"
fi
[[ -n "$expected" && "$actual" = "$expected" ]] || {
  echo "Node archive checksum mismatch" >&2; exit 1
}
tar -xzf "$scratch/$archive" -C "$scratch"
binary="$scratch/node-v${version}-${platform}-${arch}/bin/node"
[[ "$("$binary" --version)" = "v$version" ]]
"$binary" -e 'const z = require("node:zlib"); const a = require("node:assert/strict");
  a.equal(z.brotliDecompressSync(z.brotliCompressSync("security smoke")).toString(), "security smoke");
  a.equal(typeof fetch, "function"); require("node:crypto").randomUUID();'

# Rename on the same filesystem so readers never observe a partially copied binary.
staged="$(mktemp "${target}.security.XXXXXX")"
cp "$binary" "$staged"
chmod 755 "$staged"
mv -f "$staged" "$target"
staged=""
echo "$target patched: $("$target" --version) (SHA-256 verified)"
