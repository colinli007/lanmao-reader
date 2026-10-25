import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 导入失败的原因（内容格式不对、下载失败），给用户看。
final class ImportException implements Exception {
  const ImportException(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// 导入的三种来源：文件、网址、粘贴文本（书源和替换规则共用，add-replace-rules 设计 D7）。
enum ImportFrom { file, url, text }

/// 「导入」菜单按钮：选中一种来源时调用 [onSelected]。
class ImportMenuButton extends StatelessWidget {
  const ImportMenuButton({super.key, required this.onSelected});

  final ValueChanged<ImportFrom> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<ImportFrom>(
    tooltip: '导入',
    icon: const Icon(Icons.add),
    onSelected: onSelected,
    itemBuilder: (_) => const [
      PopupMenuItem(value: ImportFrom.file, child: Text('从文件导入')),
      PopupMenuItem(value: ImportFrom.url, child: Text('从网址导入')),
      PopupMenuItem(value: ImportFrom.text, child: Text('粘贴文本导入')),
    ],
  );
}

/// 按来源取到要导入的文本，用户取消时为 null。[kind] 是导入的东西（「书源」「替换规则」），[hint] 是粘贴框的提示。
/// 下载失败时抛出 [ImportException]。
Future<String?> readImportText(BuildContext context, ImportFrom from, {required String kind, required String hint}) async {
  switch (from) {
    case ImportFrom.file:
      return _pickFile(kind);
    case ImportFrom.url:
      final url = await _askInput(context, title: '从网址导入', hint: 'https://…', maxLines: 1);
      return url == null ? null : downloadText(url);
    case ImportFrom.text:
      return _askInput(context, title: '粘贴$kind JSON', hint: hint, maxLines: 8);
  }
}

/// 导入失败时的对话框。
Future<void> showImportError(BuildContext context, ImportException error) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('无法导入'),
    content: Text(error.reason),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('知道了'))],
  ),
);

/// 下载网址上的文本：主 isolate 上直接请求，不走引擎、不带 Cookie；按 UTF-8 解码（书源和规则 JSON 都是 UTF-8）。
Future<String> downloadText(String url) async {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasScheme || !uri.scheme.startsWith('http')) throw const ImportException('不是有效的网址');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final response = await (await client.getUrl(uri)).close().timeout(const Duration(seconds: 30));
    final bytes = await response.fold<List<int>>([], (all, chunk) => all..addAll(chunk)).timeout(const Duration(seconds: 30));
    if (response.statusCode >= 400) throw ImportException('下载失败：HTTP ${response.statusCode}');
    return utf8.decode(bytes, allowMalformed: true);
  } on ImportException {
    rethrow;
  } on Exception catch (e) {
    throw ImportException('下载失败：$e');
  } finally {
    client.close(force: true);
  }
}

Future<String?> _pickFile(String kind) async {
  // Android 只按 MIME 过滤，下载来的 JSON 文件常被识别成 application/octet-stream，不列上就选不了。
  // macOS 也会把 MIME 换成 UTType，octet-stream 在那里是 public.data（所有文件），所以只给 Android。
  final group = defaultTargetPlatform == TargetPlatform.android
      ? XTypeGroup(label: kind, mimeTypes: const ['application/json', 'text/plain', 'application/octet-stream'])
      : XTypeGroup(label: kind, extensions: const ['json', 'txt'], uniformTypeIdentifiers: const ['public.json', 'public.plain-text']);
  final file = await openFile(acceptedTypeGroups: [group]);
  if (file == null) return null;
  // 自己按 UTF-8 解码（和从网址导入一致）：Android 上的 XFile 是内存里的字节，它的 readAsString 不认编码，按 Latin-1 解出来中文是乱码
  return utf8.decode(await file.readAsBytes(), allowMalformed: true);
}

Future<String?> _askInput(BuildContext context, {required String title, required String hint, required int maxLines}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _InputDialog(title: title, hint: hint, maxLines: maxLines),
    );

/// 输入网址或文本的对话框，确定时把输入的文本作为结果返回。
class _InputDialog extends StatefulWidget {
  const _InputDialog({required this.title, required this.hint, required this.maxLines});

  final String title;
  final String hint;
  final int maxLines;

  @override
  State<_InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<_InputDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      minLines: widget.maxLines,
      maxLines: widget.maxLines,
      decoration: InputDecoration(hintText: widget.hint),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
      FilledButton(onPressed: () => Navigator.pop(context, _controller.text), child: const Text('确定')),
    ],
  );
}
