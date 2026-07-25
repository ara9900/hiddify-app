#!/usr/bin/env bash
# Apply TikNet Reality/Xray patches to a ray2sing checkout.
# Expects ray2sing at: hiddify-core/ray2sing  (hiddify-core go.mod replace => ./ray2sing)
# Or set RAY2SING_DIR.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RAY2SING_DIR="${RAY2SING_DIR:-$ROOT/hiddify-core/ray2sing}"
PATCH_DIR="$ROOT/patches/ray2sing"
# Submodule commit pinned by hiddify-core @ HIDDIFY_CORE_COMMIT (a82d2b8…)
EXPECTED_COMMIT="${RAY2SING_COMMIT:-c0c298d371a0bcfbcc70a6276153178ec6e9c4e1}"

if [[ ! -d "$RAY2SING_DIR/.git" && ! -f "$RAY2SING_DIR/go.mod" ]]; then
  echo "error: ray2sing not found at $RAY2SING_DIR" >&2
  echo "Clone it first, e.g.:" >&2
  echo "  git clone https://github.com/hiddify/ray2sing.git \"$RAY2SING_DIR\"" >&2
  echo "  git -C \"$RAY2SING_DIR\" checkout $EXPECTED_COMMIT" >&2
  exit 1
fi

if [[ ! -d "$PATCH_DIR" ]]; then
  echo "error: missing $PATCH_DIR" >&2
  exit 1
fi

cd "$RAY2SING_DIR"
HEAD="$(git rev-parse HEAD 2>/dev/null || true)"
if [[ -n "$HEAD" && "$HEAD" != "$EXPECTED_COMMIT"* && "$HEAD" != "$(git rev-parse --verify "${EXPECTED_COMMIT}^{commit}" 2>/dev/null || true)" ]]; then
  echo "warning: ray2sing HEAD=$HEAD (expected $EXPECTED_COMMIT); patches may fail to apply" >&2
fi

shopt -s nullglob
patches=("$PATCH_DIR"/*.patch)
if [[ ${#patches[@]} -eq 0 ]]; then
  echo "error: no .patch files in $PATCH_DIR" >&2
  exit 1
fi

for p in "${patches[@]}"; do
  echo "Applying $(basename "$p")…"
  if git apply --check "$p" 2>/dev/null; then
    git apply "$p"
  elif git apply --reverse --check "$p" 2>/dev/null; then
    echo "  already applied — skip"
  else
    echo "error: failed to apply $p" >&2
    exit 1
  fi
done

echo "✅ ray2sing patches applied in $RAY2SING_DIR"
