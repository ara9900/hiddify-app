# TikNet VPN — Project Documentation

This folder documents the **TikNet** fork of [Hiddify](https://github.com/hiddify/hiddify-app): a Sing-box based multi-platform VPN/proxy client customized for panel login and a simplified 3-tab UI.

| Document | Description |
|----------|-------------|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Code layout, startup flow, TikNet vs Hiddify mode |
| [DEVELOPMENT.md](DEVELOPMENT.md) | Clone, build, codegen, tests, debugging |
| [../TIKNET.md](../TIKNET.md) | Panel API, in-app update, GitHub Secrets for signing |

## Quick facts

- **Product name:** TikNet
- **Dart package:** `hiddify` (upstream name retained)
- **Android package:** `com.tik.net`
- **iOS bundle:** `com.tik.net`
- **Mode flag:** `lib/core/model/tiknet_config.dart` → `tikNetMode = true`
- **Core engine:** [hiddify-core](https://github.com/hiddify/hiddify-next-core) (Go, downloaded at build time)

## Repository map

```
lib/
├── main.dart / main_prod.dart   # Entry points (dev / prod)
├── bootstrap.dart               # App initialization
├── core/                        # Router, DB, prefs, theme, analytics
├── features/
│   ├── tiknet/                  # ★ TikNet product layer (login, panel, UI)
│   ├── connection/              # VPN connect/disconnect
│   ├── profile/                 # Config profiles
│   └── …                        # Other Hiddify features (hidden in TikNet mode)
├── hiddifycore/                 # gRPC bridge to Go core
└── utils/                       # Shared helpers

android/ ios/ macos/ linux/ windows/   # Platform shells
assets/translations/                    # i18n (slang)
test/                                   # Unit tests
tools/                                  # adb_pull_tiknet_log.ps1
```

## Upstream vs fork

| | Hiddify (upstream) | This fork (TikNet) |
|--|-------------------|-------------------|
| README | `README.md` (6 languages) | Product docs in `TIKNET.md` + this folder |
| UI | Full tabs (profiles, settings, logs…) | Login + 3 tabs |
| Updates | GitHub releases | Panel-controlled APK update |
| Analytics | Optional Sentry | Disabled in TikNet mode |

To restore the original Hiddify UI, set `tikNetMode = false` in `tiknet_config.dart` and rebuild — see `TIKNET.md`.
