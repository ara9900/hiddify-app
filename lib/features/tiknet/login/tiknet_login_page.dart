import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/features/tiknet/service/tiknet_api.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class TikNetLoginPage extends HookConsumerWidget {
  const TikNetLoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final panelUrlController = useTextEditingController();
    final usernameController = useTextEditingController();
    final passwordController = useTextEditingController();
    final isLoading = useState(false);
    final errorMsg = useState<String?>(null);
    final savedUrl = ref.watch(Preferences.tikNetPanelBaseUrl);
    useEffect(() {
      if (savedUrl.isNotEmpty && panelUrlController.text.isEmpty) {
        panelUrlController.text = savedUrl;
      }
      return null;
    }, [savedUrl]);

    Future<void> doLogin() async {
      final baseUrl = panelUrlController.text.trim();
      final username = usernameController.text.trim();
      final password = passwordController.text;

      if (baseUrl.isEmpty) {
        errorMsg.value = 'Panel URL is required';
        return;
      }
      if (username.isEmpty || password.isEmpty) {
        errorMsg.value = 'Username and password are required';
        return;
      }

      errorMsg.value = null;
      isLoading.value = true;
      try {
        final api = ref.read(tikNetApiProvider);
        final res = await api.login(baseUrl: baseUrl, username: username, password: password);

        await ref.read(Preferences.tikNetPanelBaseUrl.notifier).update(baseUrl);
        await ref.read(Preferences.tikNetAccessToken.notifier).update(res.accessToken);
        await ref.read(Preferences.introCompleted.notifier).update(true);

        if (res.subscriptionUrl != null && res.subscriptionUrl!.isNotEmpty) {
          await ref.read(addProfileNotifierProvider.notifier).addManual(
                url: res.subscriptionUrl!,
                userOverride: UserOverride(name: 'TikNet'),
              );
        }

        if (context.mounted) context.go('/home');
      } catch (e) {
        errorMsg.value = e is TikNetApiException ? e.message : e.toString().replaceFirst(RegExp(r'^Exception: '), '');
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
                  Text('Sign in with your panel account', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const Gap(32),
                  TextField(
                    controller: panelUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Panel URL',
                      hintText: 'https://panel.example.com',
                    ),
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                  ),
                  const Gap(16),
                  TextField(
                    controller: usernameController,
                    decoration: const InputDecoration(labelText: 'Username'),
                    textInputAction: TextInputAction.next,
                  ),
                  const Gap(16),
                  TextField(
                    controller: passwordController,
                    decoration: const InputDecoration(labelText: 'Password'),
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
                    onPressed: isLoading.value ? null : () => doLogin(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: isLoading.value ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Login'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
