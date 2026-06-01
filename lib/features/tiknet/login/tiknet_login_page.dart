import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/theme/tiknet_theme.dart';
import 'package:hiddify/features/tiknet/login/tiknet_login_flow.dart';
import 'package:hiddify/features/tiknet/login/tiknet_qr_login_parser.dart';
import 'package:hiddify/features/tiknet/service/auth_service.dart';
import 'package:hiddify/features/tiknet/service/config_service.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class TikNetLoginPage extends HookConsumerWidget {
  const TikNetLoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final savedUsername = ref.read(authServiceProvider).getSavedUsername();
    final usernameController = useTextEditingController(text: savedUsername);
    final passwordController = useTextEditingController();
    final isLoading = useState(false);
    final errorMsg = useState<String?>(null);
    final panelReady = useState(false);
    final panelReachable = useState(true);

    useEffect(() {
      ref.read(configServiceProvider).getFirstWorkingPanelUrl().then((url) {
        panelReady.value = true;
        panelReachable.value = url.isNotEmpty;
      }).catchError((_) {
        panelReady.value = true;
        panelReachable.value = false;
      });
      return null;
    }, []);

    Future<void> runLogin({required String username, required String password, String? panelBaseUrl}) async {
      errorMsg.value = null;
      isLoading.value = true;
      try {
        await performTikNetLogin(
          ref: ref,
          context: context,
          username: username,
          password: password,
          panelBaseUrl: panelBaseUrl,
        );
      } catch (e) {
        errorMsg.value = e is AuthException ? e.message : e.toString().replaceFirst(RegExp('^Exception: '), '');
      } finally {
        isLoading.value = false;
      }
    }

    Future<void> doPasswordLogin() async {
      final username = usernameController.text.trim();
      final password = passwordController.text;
      if (username.isEmpty || password.isEmpty) {
        errorMsg.value = 'نام کاربری و رمز عبور را وارد کنید.';
        return;
      }
      await runLogin(username: username, password: password);
    }

    Future<void> doQrLogin() async {
      if (isLoading.value) return;
      final raw = await ref.read(dialogNotifierProvider.notifier).showQrScanner();
      if (raw == null || raw.trim().isEmpty || !context.mounted) return;

      final payload = parseTikNetQrLogin(raw);
      if (payload == null) {
        errorMsg.value = 'QR نامعتبر است.';
        return;
      }

      if (payload is TikNetQrSubscriptionLink) {
        errorMsg.value =
            'این QR لینک اشتراک است، نه ورود.\nQR ورود باید شامل نام کاربری و رمز باشد (مثلاً username:password یا JSON).';
        return;
      }

      if (payload case TikNetQrCredentials(:final username, :final password, :final panelUrl)) {
        await runLogin(username: username, password: password, panelBaseUrl: panelUrl);
      }
    }

    final formEnabled = panelReady.value && panelReachable.value && !isLoading.value;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset(
                        'assets/images/tiknet_splash.png',
                        height: 120,
                        width: 120,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const Gap(16),
                  Text(
                    'TikNet',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const Gap(8),
                  Text(
                    'ورود با حساب پنل',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const Gap(32),
                  if (!panelReady.value)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (!panelReachable.value)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'اتصال به پنل برقرار نشد. اتصال اینترنت را بررسی کنید.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    )
                  else ...[
                    TextField(
                      controller: usernameController,
                      decoration: const InputDecoration(labelText: 'نام کاربری'),
                      textInputAction: TextInputAction.next,
                      enabled: formEnabled,
                    ),
                    const Gap(16),
                    TextField(
                      controller: passwordController,
                      decoration: const InputDecoration(labelText: 'رمز عبور'),
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      enabled: formEnabled,
                      onSubmitted: (_) => doPasswordLogin(),
                    ),
                    if (errorMsg.value != null) ...[
                      const Gap(16),
                      Text(
                        errorMsg.value!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                    const Gap(24),
                    FilledButton(
                      onPressed: formEnabled ? doPasswordLogin : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: isLoading.value
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('ورود'),
                      ),
                    ),
                    const Gap(12),
                    OutlinedButton.icon(
                      onPressed: formEnabled ? doQrLogin : null,
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      label: const Text('ورود با QR'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: TikNetColors.primary,
                        side: const BorderSide(color: TikNetColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                    const Gap(8),
                    Text(
                      'QR ورود: username:password یا JSON با username و password',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(color: TikNetColors.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
