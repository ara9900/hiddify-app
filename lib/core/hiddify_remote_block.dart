import 'package:hiddify/core/model/tiknet_config.dart';

/// TikNet: no outbound calls to Hiddify update/analytics/config hosts.
const bool blockHiddifyRemoteServices = tikNetMode;

/// True when [url] targets Hiddify project servers or official links (not panel/TikNet).
bool isHiddifyRemoteUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  final host = uri.host.toLowerCase();
  final path = uri.path.toLowerCase();

  if (host == 'hiddify.com' || host.endsWith('.hiddify.com')) return true;

  if (host == 'api.github.com' && path.contains('/hiddify/')) return true;
  if (host == 'github.com' && path.contains('/hiddify/')) return true;
  if (host == 'raw.githubusercontent.com' && path.contains('/hiddify/')) return true;

  if (host == 't.me' && path.contains('hiddify')) return true;

  return false;
}

bool isBlockedHiddifyRemoteUrl(String url) =>
    blockHiddifyRemoteServices && isHiddifyRemoteUrl(url);
