import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'online/startup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 打包的字体的许可证，关于页的「开源许可」里能看到
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['Noto Serif SC'], await rootBundle.loadString('assets/fonts/OFL.txt'));
    yield LicenseEntryWithLineBreaks(['Lucide'], await rootBundle.loadString('assets/fonts/LUCIDE_LICENSE.txt'));
  });
  runApp(ProviderScope(overrides: await startServices(), child: const NovelReaderApp()));
}
