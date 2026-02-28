import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/features/tiknet/service/auth_service.dart';
import 'package:hiddify/features/tiknet/service/config_service.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class TikNetLoginPage extends HookConsumerWidget {
  const TikNetLoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final usernameController = useTextEditingController();
    final passwordController = useTextEditingController();
    final isLoading = useState(false);
    final errorMsg = useState<String?>(null);
    final panelUrl = useState<String?>(null);
    final panelUrlLoading = useState(true);
    useEffect(() {
      ref.read(configServiceProvider).getFirstWorkingPanelUrl().then((url) {
        panelUrl.value = url;
        panelUrlLoading.value = false;
      }).catchError((_) {
        panelUrlLoading.value = false;
        panelUrl.value = null;
      });
      return null;
    }, []);

    Future<void> doLogin() async {
      final username = usernameController.text.trim();
      final password = passwordController.text;

      if (username.isEmpty || password.isEmpty) {
        errorMsg.value = 'نام کاربری و رمز عبور را وارد کنید.';
        return;
      }

      errorMsg.value = null;
      isLoading.value = true;
      try {
        final auth = ref.read(authServiceProvider);
        await auth.login(username, password);

        await ref.read(Preferences.introCompleted.notifier).update(true);

        final subscriptionUrl = auth.getSubscriptionUrl();
        if (subscriptionUrl != null && subscriptionUrl.isNotEmpty) {
          await ref.read(addProfileNotifierProvider.notifier).addManual(
                url: subscriptionUrl,
                userOverride: UserOverride(name: 'TikNet'),
              );
        }

        if (context.mounted) context.go('/home');
      } catch (e) {
        errorMsg.value = e is AuthException ? e.message : e.toString().replaceFirst(RegExp(r'^Exception: '), '');
      } finally {
        isLoading.value = false;
      }
    }

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
                  Text('TikNet', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const Gap(8),
                  Text('ورود با حساب پنل', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  if (panelUrl.value != null && panelUrl.value!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('پنل: ${panelUrl.value}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ),
                  const Gap(32),
                  if (panelUrlLoading.value)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (panelUrl.value == null || panelUrl.value!.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text('اتصال به پنل برقرار نشد. اتصال اینترنت را بررسی کنید.', style: TextStyle(color: theme.colorScheme.error)),
                    )
                  else ...[
                  TextField(
                    controller: usernameController,
                    decoration: const InputDecoration(labelText: 'نام کاربری'),
                    textInputAction: TextInputAction.next,
                  ),
                  const Gap(16),
                  TextField(
                    controller: passwordController,
                    decoration: const InputDecoration(labelText: 'رمز عبور'),
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => doLogin(),
                  ),
                  if (errorMsg.value != null) ...[
                    const Gap(16),
                    Text(errorMsg.value!, style: TextStyle(color: theme.colorScheme.error)),
                  ],
                  const Gap(24),
                  FilledButton(
                    onPressed: (isLoading.value || panelUrlLoading.value || panelUrl.value == null || panelUrl.value!.isEmpty) ? null : () => doLogin(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: isLoading.value ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('ورود'),
                    ),
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
