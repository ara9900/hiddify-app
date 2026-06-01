/// TikNet mode: when true, app shows login, user info, and only 3 tabs.
const bool tikNetMode = true;

/// Blocks update checks, Sentry, and other calls to Hiddify-hosted URLs (see [hiddify_remote_block.dart]).
const bool tikNetBlocksHiddifyRemote = tikNetMode;

/// Default panel base URL (user can override in login screen).
const String tikNetPanelBaseUrlDefault = '';
