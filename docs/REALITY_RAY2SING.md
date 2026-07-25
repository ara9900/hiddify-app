# Reality / ray2sing patches (TikNet)

## Problem

Stock Hiddify (and TikNet) convert share links with **ray2sing** before sing-box/Xray runs.

On the ray2sing commit vendored by current `hiddify-core` (`c0c298d…`):

1. **Xray conversion is hard-disabled** in `convert.go`:
   `if false && (useXrayWhenPossible || …)` — so the app toggle “use Xray core when possible” does nothing at parse time.
2. **sing-box Reality mapping drops `spx` (spiderX)** — only `pbk` / `sid` are set.
3. The Xray path *does* map `spiderX` from `spx`, but is unreachable because of (1).
4. Empty Reality `fp` on the Xray path did not default to `chrome` (sing-box path does).

Same Reality link working in **v2rayNG** but failing in Hiddify (both core toggles) matches this conversion gap — not a TikNet-only bug.

## Patch

`patches/ray2sing/0001-reenable-xray-reality-mapping.patch` (against ray2sing `c0c298d`):

- Re-enable Xray conversion when `useXrayWhenPossible` or `&core=xray`.
- Default empty TLS/Reality fingerprint to `chrome` on the Xray path.

**Does not** merge upstream Hiddify *app* commits — only patches the core dependency tree at build time.

## Pins (must stay in sync with CI)

| Dep | Commit / note |
|-----|----------------|
| hiddify-core | `a82d2b8f047ce769caad42ad9d3ab2c0ef53208a` (`HIDDIFY_CORE_COMMIT` in `build-apk.yml`) |
| ray2sing (submodule) | `c0c298d371a0bcfbcc70a6276153178ec6e9c4e1` |
| hiddify-sing-box | `3a1c923e306d5b39cde8f2c02ec9dd556ea112d3` |

`hiddify-core` `go.mod` uses `replace github.com/hiddify/ray2sing => ./ray2sing` — patches must land in **`hiddify-core/ray2sing`**, not a sibling clone.

## Scripts

```bash
# Clone pinned core + deps and apply patches (no AAR)
bash scripts/prepare-patched-core.sh

# Also build AAR (Linux/CI with Go + Android NDK + npm)
BUILD_ANDROID_AAR=1 bash scripts/prepare-patched-core.sh

# Or only apply patches if tree already exists
bash scripts/apply-ray2sing-patches.sh
```

Makefile helpers: `make patch-ray2sing`, `make prepare-patched-core`, `make build-android-libs` (after prepare).

## CI

`build-apk.yml` workflow_dispatch input **`build_patched_core`**:

- `false` (default): download prebuilt AAR from `CORE_AAR_URL` (current behavior). Reality Xray fix **not** in binary.
- `true`: prepare patched core and `make build-android-libs`, then build the APK.

Local Windows: Go/NDK/gomobile are usually missing — use CI with `build_patched_core=true`.

## App (Dart) mitigations

On TikNet first launch after this version (one-shot prefs flag):

- Force **mux / TLS fragment / mixed SNI / padding off** (safer for Reality).
- Enable **`use-xray-core-when-possible`** (needs patched AAR + **reimport** of profiles for parse-time conversion).

Ping (`tiknet_node_pings_notifier`) stays on-demand only — **no auto-connect**.

## How to test

1. CI: run **Build APK** with `build_patched_core=true`; install ARM64 APK.
2. In app: confirm Settings → use Xray when possible is on (or enable + **sync/reimport** subscription).
3. Import / sync a Reality VLESS link that works in v2rayNG (no need to paste secrets into issues).
4. Connect; confirm tunnel up. Optional: ping from server picker — must **not** start VPN by itself.
5. Control: same APK built with `build_patched_core=false` should still show the old Xray-toggle no-op for conversion.

## AAR layout note

Prebuilt release tarball (`hiddify-lib-android.tar.gz`) differs from a local `hiddify-core.aar`. Patched builds copy `hiddify-core/bin/hiddify-core.aar` → `android/app/libs/`. Ensure the Android Gradle/FFI side expects that artifact name (same as `make build-android-libs`).
