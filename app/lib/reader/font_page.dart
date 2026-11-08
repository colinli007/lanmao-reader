import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/icons.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'reader_fonts.dart';
import 'reader_settings.dart';

class FontPage extends ConsumerStatefulWidget {
  const FontPage({super.key});

  @override
  ConsumerState<FontPage> createState() => _FontPageState();
}

class _FontPageState extends ConsumerState<FontPage> {
  bool _busy = false;

  void _select(String id) {
    ref.read(readerFontsProvider).warning = null;
    final settings = ref.read(readerSettingsProvider);
    ref.read(readerSettingsProvider.notifier).update(settings.copyWith(fontId: id));
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        await showMessageDialog(context, title: '无法使用字体', message: error is FormatException ? error.message : '字体文件无法读取或保存，请重试。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() => _run(() async {
    // Android 按 MIME 过滤；某些下载器把字体标成二进制文件，内容仍要在导入时验证。
    final type = defaultTargetPlatform == TargetPlatform.android
        ? const XTypeGroup(
            label: '字体',
            mimeTypes: ['font/ttf', 'font/otf', 'application/x-font-ttf', 'application/x-font-opentype', 'application/octet-stream'],
          )
        : const XTypeGroup(
            label: '字体',
            extensions: ['ttf', 'otf'],
            uniformTypeIdentifiers: ['public.truetype-ttf-font', 'public.opentype-font'],
          );
    final file = await openFile(acceptedTypeGroups: [type]);
    if (file == null || !mounted) return;
    final fonts = ref.read(readerFontsProvider);
    final font = await fonts.import(file.name, await file.readAsBytes());
    if (mounted) _select(font.id);
  });

  Future<void> _choose(ReaderFont font) => _run(() async {
    await ref.read(readerFontsProvider).load(font.id);
    if (mounted) _select(font.id);
  });

  Future<void> _remove(ReaderFont font) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除字体？',
      message: '删除「${font.name}」的应用内副本。正在使用此字体时，将切回系统字体。',
      confirmLabel: '删除',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    await _run(() async {
      final settings = ref.read(readerSettingsProvider.notifier);
      await ref.read(readerFontsProvider).remove(font.id);
      settings.resetFontIfSelected(font.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final fonts = ref.watch(readerFontsProvider);
    final settings = ref.watch(readerSettingsProvider);
    final family = fonts.familyFor(settings.fontId);
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.groupedBackground,
      appBar: AppBar(
        title: const Text('字体'),
        backgroundColor: colors.groupedBackground,
        actions: [TextButton(onPressed: _busy ? null : _import, child: const Text('导入字体'))],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.item),
        children: [
          if (_busy) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.page),
            child: Text('山色有无中，江流天地外。\n阅读，让故事慢慢展开。', style: TextStyle(fontFamily: family, fontSize: 22, height: 1.8)),
          ),
          if (fonts.warning case final warning?)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.page),
              child: Text(warning, style: TextStyle(color: colors.textSecondary)),
            ),
          SettingsGroup(
            children: [
              ListTile(
                title: const Text('系统字体'),
                selected: family == null,
                trailing: family == null ? const Icon(LucideIcons.check) : null,
                onTap: _busy ? null : () => _select(''),
              ),
              for (final font in fonts.entries)
                ListTile(
                  title: Text(font.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                  selected: family == font.family,
                  leading: family == font.family ? const Icon(LucideIcons.check) : null,
                  trailing: IconButton(
                    tooltip: '删除字体 ${font.name}',
                    onPressed: _busy ? null : () => _remove(font),
                    icon: const Icon(LucideIcons.trash2, size: 20),
                  ),
                  onTap: _busy ? null : () => _choose(font),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.page),
            child: Text('支持 TTF、OTF 文件。导入后保存在本机，对所有书籍生效；字体缺少的字符使用系统字体显示。', style: TextStyle(color: colors.textSecondary)),
          ),
        ],
      ),
    );
  }
}
