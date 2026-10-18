import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// 书源日志：新的在前，显示时间、书源名（书源已删除时显示地址）、字段和内容。
class SourceLogPage extends ConsumerWidget {
  const SourceLogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(sourceLogProvider);
    final sources = ref.watch(sourceRepositoryProvider);
    final entries = log.entries;
    return Scaffold(
      appBar: AppBar(
        title: const Text('书源日志'),
        actions: [IconButton(tooltip: '清空', icon: const Icon(Icons.delete_sweep_outlined), onPressed: log.clear)],
      ),
      body: entries.isEmpty
          ? const Center(child: Text('没有日志'))
          : ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final entry = entries[index];
                final url = entry.sourceUrl;
                final name = url == null ? '存储' : (sources[url]?.source.bookSourceName ?? url);
                final time = TimeOfDay.fromDateTime(entry.time).format(context);
                return ListTile(
                  dense: true,
                  title: SelectableText(entry.message),
                  subtitle: Text([time, name, ?entry.field].join(' · ')),
                );
              },
            ),
    );
  }
}
