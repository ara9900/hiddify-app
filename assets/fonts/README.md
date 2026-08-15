# Fonts

Bundled fonts were removed from this fork to keep the repo lean.

- **Persian (TikNet UI):** Vazirmatn via `google_fonts` in `lib/core/theme/tiknet_theme.dart`
- **Windows emoji flags:** `Segoe UI Emoji` system font via `lib/core/theme/font_families.dart`

## Optional: bundled emoji subset

To restore a bundled emoji font (upstream Hiddify behavior), follow instructions in `emoji_source.txt` using [noto-emoji](https://github.com/hiddify-com/noto-emoji) and add `Emoji.ttf` here, then register in `pubspec.yaml`.
