import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../app_info.dart';

/// 安装包的版本号（设计 D4）：Flutter 构建时从 pubspec.yaml 写进安装包，这里读回来。
final appVersionProvider = FutureProvider<String>((ref) async => (await PackageInfo.fromPlatform()).version);

/// 社区版的免责声明，README 开头用同样的文字。
const disclaimer = '本软件不提供任何内容。书源由用户自行导入，通过书源获取的内容与本软件无关。';

/// 关于页（settings「关于页」）：版本、开源协议、源代码地址、免责声明、第三方许可。
class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(appVersionProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        children: [
          ListTile(title: const Text(appName), subtitle: Text(version == null ? '' : '版本 $version')),
          const ListTile(title: Text('开源协议'), subtitle: Text('GPL-3.0')),
          ListTile(
            title: const Text('源代码'),
            subtitle: const Text(sourceCodeUrl),
            trailing: const Icon(Icons.copy),
            onTap: () async {
              await Clipboard.setData(const ClipboardData(text: sourceCodeUrl));
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制')));
            },
          ),
          const ListTile(title: Text('免责声明'), subtitle: Text(disclaimer)),
          ListTile(
            title: const Text('开源许可'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(context: context, applicationName: appName, applicationVersion: version),
          ),
        ],
      ),
    );
  }
}
