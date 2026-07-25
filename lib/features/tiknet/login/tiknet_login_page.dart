import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/router/deep_linking/my_app_links.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/router/go_router/refresh_listenable.dart';
import 'package:hiddify/core/theme/tiknet_theme.dart';
import 'package:hiddify/features/tiknet/login/tiknet_login_flow.dart';
import 'package:hiddify/features/tiknet/login/tiknet_qr_login_parser.dart';
import 'package:hiddify/features/tiknet/model/tiknet_public_config.dart';
import 'package:hiddify/features/tiknet/service/auth_service.dart';
import 'package:hiddify/features/tiknet/service/config_service.dart';
import 'package:hiddify/features/tiknet/service/tiknet_api.dart';
import 'package:hiddify/utils/uri_utils.dart';
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
    final publicConfig = useState(const TikNetPublicConfig());
    final obscure = useState(true);
    final deepLinkHandled = useRef(false);
    final pulse = useAnimationController(duration: const Duration(milliseconds: 2800))..repeat(reverse: true);

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

    Future<void> runTokenLogin({required String token, String? panelBaseUrl}) async {
      errorMsg.value = null;
      isLoading.value = true;
      try {
        await performTikNetLoginWithToken(
          ref: ref,
          context: context,
          token: token,
          panelBaseUrl: panelBaseUrl,
        );
      } catch (e) {
        errorMsg.value = e is AuthException ? e.message : e.toString().replaceFirst(RegExp('^Exception: '), '');
      } finally {
        isLoading.value = false;
      }
    }

    Future<void> consumeLoginLink(String raw) async {
      final payload = parseTikNetQrLogin(raw);
      if (payload == null) return;
      if (payload is TikNetQrLoginToken) {
        await runTokenLogin(token: payload.token, panelBaseUrl: payload.panelUrl);
        return;
      }
      if (payload case TikNetQrCredentials(:final username, :final password, :final panelUrl)) {
        await runLogin(username: username, password: password, panelBaseUrl: panelUrl);
      }
    }

    useEffect(() {
      ref.read(configServiceProvider).getFirstWorkingPanelUrl().then((url) async {
        panelReady.value = true;
        panelReachable.value = url.isNotEmpty;
        if (url.isNotEmpty) {
          try {
            publicConfig.value = await ref.read(tikNetApiProvider).getPublicConfig(baseUrl: url);
          } catch (_) {
            publicConfig.value = const TikNetPublicConfig();
          }
        }
      }).catchError((_) {
        panelReady.value = true;
        panelReachable.value = false;
      });
      return null;
    }, []);

    useEffect(() {
      Future<void> tryPending() async {
        if (deepLinkHandled.value || isLoading.value) return;
        final pending = pendingTikNetLoginLink;
        if (pending == null || pending.isEmpty) return;
        deepLinkHandled.value = true;
        pendingTikNetLoginLink = null;
        await consumeLoginLink(pending);
      }

      tryPending();
      final sub = ref.listenManual(myAppLinksProvider, (_, next) {
        final link = next.value;
        if (link == null || !isTikNetLoginDeepLink(link)) return;
        if (deepLinkHandled.value || isLoading.value) {
          pendingTikNetLoginLink = link;
          return;
        }
        deepLinkHandled.value = true;
        pendingTikNetLoginLink = null;
        consumeLoginLink(link);
      });
      return sub.close;
    }, []);

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
        errorMsg.value = 'کد QR ورود نامعتبر است.';
        return;
      }

      if (payload is TikNetQrSubscriptionLink) {
        errorMsg.value = 'این QR برای ورود نیست. لطفاً QR ورود حساب را اسکن کنید.';
        return;
      }

      if (payload is TikNetQrLoginToken) {
        await runTokenLogin(token: payload.token, panelBaseUrl: payload.panelUrl);
        return;
      }

      if (payload case TikNetQrCredentials(:final username, :final password, :final panelUrl)) {
        await runLogin(username: username, password: password, panelBaseUrl: panelUrl);
      }
    }

    final formEnabled = panelReady.value && panelReachable.value && !isLoading.value;
    final shop = publicConfig.value;
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      backgroundColor: TikNetColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _LoginAtmosphere(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Gap(size.height < 700 ? 12 : 28),
                      _BrandHero(pulse: pulse)
                          .animate()
                          .fadeIn(duration: 700.ms, curve: Curves.easeOut)
                          .scale(begin: const Offset(0.86, 0.86), end: const Offset(1, 1), duration: 800.ms, curve: Curves.easeOutBack),
                      const Gap(18),
                      Text(
                        'TikNet',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      )
                          .animate()
                          .fadeIn(delay: 120.ms, duration: 500.ms)
                          .slideY(begin: 0.2, end: 0, delay: 120.ms, duration: 500.ms, curve: Curves.easeOutCubic),
                      const Gap(6),
                      Text(
                        'ورود امن به حساب شما',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: TikNetColors.onSurfaceVariant,
                        ),
                      )
                          .animate()
                          .fadeIn(delay: 200.ms, duration: 500.ms)
                          .slideY(begin: 0.15, end: 0, delay: 200.ms, duration: 500.ms),
                      const Gap(28),
                      if (!panelReady.value)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (!panelReachable.value)
                        _GlassCard(
                          child: Text(
                            'اتصال به پنل برقرار نشد. اتصال اینترنت را بررسی کنید.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: theme.colorScheme.error, height: 1.5),
                          ),
                        )
                      else
                        _GlassCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextField(
                                controller: usernameController,
                                decoration: _fieldDecoration(
                                  label: 'نام کاربری',
                                  icon: Icons.person_outline_rounded,
                                ),
                                textInputAction: TextInputAction.next,
                                enabled: formEnabled,
                              ),
                              const Gap(14),
                              TextField(
                                controller: passwordController,
                                decoration: _fieldDecoration(
                                  label: 'رمز عبور',
                                  icon: Icons.lock_outline_rounded,
                                  suffix: IconButton(
                                    onPressed: () => obscure.value = !obscure.value,
                                    icon: Icon(
                                      obscure.value ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                      color: TikNetColors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                obscureText: obscure.value,
                                textInputAction: TextInputAction.done,
                                enabled: formEnabled,
                                onSubmitted: (_) => doPasswordLogin(),
                              ),
                              if (errorMsg.value != null) ...[
                                const Gap(14),
                                Text(
                                  errorMsg.value!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: theme.colorScheme.error, height: 1.4),
                                ),
                              ],
                              const Gap(22),
                              FilledButton(
                                onPressed: formEnabled ? doPasswordLogin : null,
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(52),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                                child: isLoading.value
                                    ? const SizedBox(
                                        height: 22,
                                        width: 22,
                                        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                                      )
                                    : const Text('ورود'),
                              ),
                              const Gap(12),
                              OutlinedButton.icon(
                                onPressed: formEnabled ? doQrLogin : null,
                                icon: const Icon(Icons.qr_code_scanner_rounded),
                                label: const Text('ورود با QR'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: TikNetColors.primary,
                                  side: BorderSide(color: TikNetColors.primary.withValues(alpha: 0.7)),
                                  minimumSize: const Size.fromHeight(50),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                              ),
                              if (shop.showTelegramShop) ...[
                                const Gap(12),
                                FilledButton.tonalIcon(
                                  onPressed: formEnabled
                                      ? () => UriUtils.tryLaunch(Uri.parse(shop.telegramShopUrl!))
                                      : null,
                                  icon: const Icon(Icons.shopping_bag_outlined),
                                  label: Text(
                                    (shop.telegramShopLabel?.trim().isNotEmpty == true)
                                        ? shop.telegramShopLabel!.trim()
                                        : 'خرید و تمدید',
                                  ),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(50),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        )
                            .animate()
                            .fadeIn(delay: 280.ms, duration: 600.ms)
                            .slideY(begin: 0.12, end: 0, delay: 280.ms, duration: 650.ms, curve: Curves.easeOutCubic),
                      const Gap(24),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: TikNetColors.onSurfaceVariant),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.04),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: TikNetColors.primary, width: 1.4),
      ),
    );
  }
}

class _BrandHero extends StatelessWidget {
  const _BrandHero({required this.pulse});

  final AnimationController pulse;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(pulse.value);
        final glow = 18 + (t * 16);
        return Center(
          child: Container(
            width: 118,
            height: 118,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: TikNetColors.primary.withValues(alpha: 0.28 + t * 0.22),
                  blurRadius: glow,
                  spreadRadius: 2 + t * 4,
                ),
                BoxShadow(
                  color: const Color(0xFF22D3EE).withValues(alpha: 0.12 + t * 0.1),
                  blurRadius: glow + 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              TikNetColors.primary.withValues(alpha: 0.35),
              Colors.white.withValues(alpha: 0.06),
            ],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Image.asset(
          'assets/images/tiknet_shield.png',
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: Colors.white.withValues(alpha: 0.05),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 28,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _LoginAtmosphere extends StatefulWidget {
  const _LoginAtmosphere();

  @override
  State<_LoginAtmosphere> createState() => _LoginAtmosphereState();
}

class _LoginAtmosphereState extends State<_LoginAtmosphere> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value * math.pi * 2;
        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: TikNetColors.background),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(-0.75 + 0.15 * math.sin(t), -0.85),
                  radius: 1.15,
                  colors: [
                    TikNetColors.primary.withValues(alpha: 0.34),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.9, 0.75 + 0.1 * math.cos(t)),
                  radius: 1.05,
                  colors: [
                    const Color(0xFF22D3EE).withValues(alpha: 0.16),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.55),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
