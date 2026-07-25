#!/usr/bin/env bash
# Prepare hiddify-core + pinned ray2sing/hiddify-sing-box, then apply TikNet Reality patches.
# Does NOT merge upstream app commits — only clones pinned core deps next to/inside this repo.
#
# Usage (from app repo root, Linux/macOS/Git Bash/CI):
#   bash scripts/prepare-patched-core.sh
#   BUILD_ANDROID_AAR=1 bash scripts/prepare-patched-core.sh   # also gomobile-bind AAR
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

HIDDIFY_CORE_COMMIT="${HIDDIFY_CORE_COMMIT:-a82d2b8f047ce769caad42ad9d3ab2c0ef53208a}"
RAY2SING_COMMIT="${RAY2SING_COMMIT:-c0c298d371a0bcfbcc70a6276153178ec6e9c4e1}"
SINGBOX_COMMIT="${SINGBOX_COMMIT:-3a1c923e306d5b39cde8f2c02ec9dd556ea112d3}"
BUILD_ANDROID_AAR="${BUILD_ANDROID_AAR:-0}"

echo "==> Cloning hiddify-core @ ${HIDDIFY_CORE_COMMIT}"
rm -rf hiddify-core
git clone --filter=blob:none https://github.com/hiddify/hiddify-core.git hiddify-core
git -C hiddify-core fetch --depth 1 origin "$HIDDIFY_CORE_COMMIT"
git -C hiddify-core checkout "$HIDDIFY_CORE_COMMIT"

echo "==> Cloning ray2sing @ ${RAY2SING_COMMIT} into hiddify-core/ray2sing"
# Prefer HTTPS — upstream .gitmodules uses git@ which fails on CI without SSH keys.
rm -rf hiddify-core/ray2sing
git clone https://github.com/hiddify/ray2sing.git hiddify-core/ray2sing
git -C hiddify-core/ray2sing checkout "$RAY2SING_COMMIT"

echo "==> Cloning hiddify-sing-box @ ${SINGBOX_COMMIT} into hiddify-core/hiddify-sing-box"
rm -rf hiddify-core/hiddify-sing-box
git clone https://github.com/hiddify/hiddify-sing-box.git hiddify-core/hiddify-sing-box
git -C hiddify-core/hiddify-sing-box fetch --depth 1 origin "$SINGBOX_COMMIT" || true
git -C hiddify-core/hiddify-sing-box checkout "$SINGBOX_COMMIT"

echo "==> Applying TikNet ray2sing patches"
RAY2SING_DIR="$ROOT/hiddify-core/ray2sing" bash "$ROOT/scripts/apply-ray2sing-patches.sh"

if [[ "$BUILD_ANDROID_AAR" != "1" ]]; then
  echo
  echo "Core tree ready (patched). To build the Android AAR:"
  echo "  BUILD_ANDROID_AAR=1 bash scripts/prepare-patched-core.sh"
  echo "  # or: make build-android-libs"
  echo
  echo "Note: local Windows hosts usually lack Go/NDK/gomobile — use GitHub Actions"
  echo "with workflow input build_patched_core=true."
  exit 0
fi

echo "==> Building Android AAR (gomobile) — requires Go, Android NDK, npm"
mkdir -p android/app/libs
make -C hiddify-core android
AAR="hiddify-core/bin/hiddify-core.aar"
if [[ ! -f "$AAR" ]]; then
  echo "error: expected AAR at $AAR" >&2
  exit 1
fi
cp -f "$AAR" android/app/libs/hiddify-core.aar
echo "✅ Patched AAR → android/app/libs/hiddify-core.aar"
ls -lh android/app/libs/hiddify-core.aar
