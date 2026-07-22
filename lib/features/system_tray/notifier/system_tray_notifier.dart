import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/window/notifier/window_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

part 'system_tray_notifier.g.dart';

const _trayIconAsset = 'assets/images/tiknet_shield.png';

@Riverpod(keepAlive: true)
class SystemTrayNotifier extends _$SystemTrayNotifier with TrayListener, AppLogger {
  bool listenerAdded = false;
  @override
  Future<void> build() async {
    assert(PlatformUtils.isDesktop);
    if (!listenerAdded) {
      trayManager.addListener(this);
      listenerAdded = true;
    }
    await _initializeTray();
  }

  Future<void> _initializeTray() async {
    final t = await ref.watch(translationsProvider.future);
    final urlTestDelay = await ref
        .watch(activeProxyNotifierProvider.future)
        .catchError((e) {
          loggy.warning("error getting active proxy", e);
          return OutboundInfo(urlTestDelay: 0);
        })
        .then((connection) => connection.urlTestDelay);
    final connection = await ref
        .watch(connectionNotifierProvider.future)
        .catchError((e) {
          loggy.warning("error getting connection status", e);
          return const ConnectionStatus.disconnected();
        })
        .then((connection) => _modifyConnectionStatus(connection, urlTestDelay));
    final serviceMode = ref.watch(ConfigOptions.serviceMode);

    await trayManager.setIcon(_trayIconPath(connection), isTemplate: PlatformUtils.isMacOS);
    if (!PlatformUtils.isLinux) await trayManager.setToolTip(_trayTooltip(connection, urlTestDelay, t));
    await trayManager.setContextMenu(_trayMenu(connection, serviceMode, t));
  }

  Menu _trayMenu(ConnectionStatus connection, ServiceMode serviceMode, Translations t) => Menu(
    items: [
      if (PlatformUtils.isLinux) ...[MenuItem(key: 'dashboard', label: t.common.dashboard), MenuItem.separator()],
      MenuItem(
        key: 'connection',
        label: switch (connection) {
          Disconnected() => t.connection.connect,
          Connecting() => t.connection.connecting,
          Connected() => t.connection.disconnect,
          Disconnecting() => t.connection.disconnecting,
        },
        disabled: connection.isSwitching,
      ),
      MenuItem.submenu(
        label: t.pages.settings.inbound.serviceMode,
        submenu: Menu(
          items: [
            ...ServiceMode.values.map(
              (e) => MenuItem.checkbox(checked: e == serviceMode, key: e.name, label: e.present(t)),
            ),
          ],
        ),
      ),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: t.common.quit),
    ],
  );

  String _trayIconPath(ConnectionStatus status) => _trayIconAsset;

  String _trayTooltip(ConnectionStatus connection, int urlTestDelay, Translations t) {
    final r = "${Constants.appName} - ${connection.present(t)}";
    if (connection is Connected) {
      if (Platform.isMacOS) windowManager.setBadgeLabel("${urlTestDelay}ms");
      return '$r : ${urlTestDelay}ms';
    } else {
      if (Platform.isMacOS) windowManager.setBadgeLabel("-ms");
      return r;
    }
  }

  ConnectionStatus _modifyConnectionStatus(ConnectionStatus connection, int urlTestDelay) {
    if (connection is Connected) {
      return urlTestDelay > 0 && urlTestDelay < 65000 ? const Connected() : const Connecting();
    } else {
      return connection;
    }
  }

  @override
  Future<void> onTrayMenuItemClick(MenuItem menuItem) async {
    if (menuItem.key == 'dashboard') {
      await ref.read(windowNotifierProvider.notifier).show();
    } else if (menuItem.key == 'connection') {
      await ref.read(connectionNotifierProvider.notifier).toggleConnection();
    } else if (menuItem.key == 'quit') {
      await ref.read(windowNotifierProvider.notifier).exit();
    } else {
      final newMode = ServiceMode.values.byName(menuItem.key!);
      loggy.debug("switching service mode: [$newMode]");
      await ref.read(ConfigOptions.serviceMode.notifier).update(newMode);
    }
  }

  @override
  Future<void> onTrayIconMouseDown() async {
    await ref.read(windowNotifierProvider.notifier).showOrHide();
  }

  @override
  Future<void> onTrayIconRightMouseDown() async {
    await trayManager.popUpContextMenu();
  }
}

