import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rule_engine/rule_engine.dart' show defaultUserAgent;

import '../ui/icons.dart';
import '../ui/widgets.dart';

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
    icon: const Icon(LucideIcons.plus),
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
      final url = await showInputDialog(context, title: '从网址导入', hint: 'https://…', maxLines: 1);
      return url == null ? null : downloadText(url);
    case ImportFrom.text:
      return showInputDialog(context, title: '粘贴$kind JSON', hint: hint, maxLines: 8);
  }
}

/// 导入失败时的对话框。
Future<void> showImportError(BuildContext context, ImportException error) =>
    showMessageDialog(context, title: '无法导入', message: error.reason);

/// 网址末尾的这个标记表示请求不带 User-Agent（Legado 的导入写法）。
const String _withoutUserAgentMark = '#requestWithoutUA';

/// 下载网址上的文本：主 isolate 上直接请求，不走引擎、不带 Cookie；按 UTF-8 解码（书源和规则 JSON 都是 UTF-8）。
/// User-Agent 和书源请求的默认值相同，网址以 [_withoutUserAgentMark] 结尾时去掉标记、不带 User-Agent（improve-source-import 设计 D4）。
Future<String> downloadText(String url) async {
  var address = url.trim();
  final withoutUserAgent = address.endsWith(_withoutUserAgentMark);
  if (withoutUserAgent) address = address.substring(0, address.length - _withoutUserAgentMark.length);
  final uri = Uri.tryParse(address);
  if (uri == null || !uri.hasScheme || !uri.scheme.startsWith('http')) throw const ImportException('不是有效的网址');
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..userAgent = withoutUserAgent ? null : defaultUserAgent;
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
