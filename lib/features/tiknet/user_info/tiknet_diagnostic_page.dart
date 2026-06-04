import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/theme/tiknet_theme.dart';
import 'package:hiddify/features/tiknet/service/tiknet_diagnostic_log.dart';
import 'package:share_plus/share_plus.dart';

class TikNetDiagnosticPage extends StatelessWidget {
  const TikNetDiagnosticPage({super.key});

  @override
  Widget build(BuildContext context) {
    final text = TikNetDiagnosticLog.exportText();
    final path = TikNetDiagnosticLog.filePath;

    return Scaffold(
      appBar: AppBar(
        title: const Text('گزارش تشخیصی'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'پاک کردن',
            onPressed: () async {
              await TikNetDiagnosticLog.clear();
              if (context.mounted) {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const TikNetDiagnosticPage()),
                );
              }
            },
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (path != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'فایل: $path',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: TikNetColors.onSurfaceVariant),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: text.isEmpty
                        ? null
                        : () async {
                            await TikNetDiagnosticLog.copyToClipboard();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('لاگ در حافظه کپی شد')),
                              );
                            }
                          },
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('کپی'),
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: text.isEmpty
                        ? null
                        : () => Share.share(text, subject: 'TikNet diagnostic log'),
                    icon: const Icon(Icons.share_rounded),
                    label: const Text('اشتراک'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: text.isEmpty
                ? const Center(child: Text('هنوز رویدادی ثبت نشده. اتصال/بروزرسانی را امتحان کنید.'))
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    child: SelectableText(
                      text,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.35),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
