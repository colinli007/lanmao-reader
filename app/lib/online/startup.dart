import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/providers.dart';
import '../reader/reader_settings.dart';
import '../storage/database.dart';
import '../storage/write_queue.dart';
import 'engine_stack.dart';
import 'online_content_source.dart';
import 'providers.dart';
import 'source_engine.dart';
import 'source_log.dart';
import 'source_repository.dart';

/// 启动顺序（设计 D1）：打开数据库 → 清理浏览中的书 → 载入书源级状态和 Cookie → 建 RuleHost 和 worker 池 → 载入书源。
/// 返回给 ProviderScope 的覆盖项。[database] 是集成测试用的临时数据库，默认打开应用支持目录下的数据库。
Future<List<Override>> startServices({AppDatabase? database}) async {
  final db = database ?? AppDatabase.open();
  await db.purgeBrowsingBooks();
  final log = SourceLogBuffer();
  final queue = WriteQueue(onError: log.addStorageError);
  final engine = await EngineStack.open(db, queue, onLog: log.addSourceLog);
  final sources = await SourceRepository.load(db);
  final settings = await db.loadSettings();
  // 进入后台时等落盘队列清空，app 被杀时不丢最后几次写入（监听器注册到 binding 上，整个运行期间有效）
  AppLifecycleListener(onHide: queue.flush, onPause: queue.flush);
  final sourceEngine = PoolSourceEngine(engine.pool);
  return [
    databaseProvider.overrideWithValue(db),
    initialSettingsProvider.overrideWithValue(settings),
    contentSourceProvider.overrideWithValue(OnlineContentSource(sourceEngine, sources)),
    sourceEngineProvider.overrideWithValue(sourceEngine),
    sourceRepositoryProvider.overrideWith((ref) => sources),
    sourceLogProvider.overrideWith((ref) => log),
  ];
}
