import 'package:flutter/material.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/deep_linking/my_app_links.dart';
import 'package:hiddify/features/tiknet/login/tiknet_qr_login_parser.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// For temporary storage of the link received from AppLinks (profile import).
String newUrlFromAppLink = '';

/// Pending TikNet login deep link (`tiknet://login?token=...`).
String? pendingTikNetLoginLink;

class RefreshListenable extends ChangeNotifier {
  RefreshListenable(this.ref) {
    ref.listen(myAppLinksProvider, (_, next) {
      if (next.value != null) {
        final link = next.value!;
        if (isTikNetLoginDeepLink(link)) {
          pendingTikNetLoginLink = link;
        } else {
          newUrlFromAppLink = link;
        }
        notifyListeners();
      }
    });
    ref.listen(Preferences.introCompleted, (_, _) => notifyListeners());
  }
  final Ref ref;
}
