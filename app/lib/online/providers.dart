import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'source_engine.dart';
import 'source_log.dart';
import 'source_repository.dart';

// 这些都在启动时创建，在 main 里覆盖（online/startup.dart）。

final sourceEngineProvider = Provider<SourceEngine>((ref) => throw UnimplementedError('sourceEngineProvider 需要在启动时覆盖'));

final sourceRepositoryProvider = ChangeNotifierProvider<SourceRepository>(
  (ref) => throw UnimplementedError('sourceRepositoryProvider 需要在启动时覆盖'),
);

final sourceLogProvider = ChangeNotifierProvider<SourceLogBuffer>((ref) => throw UnimplementedError('sourceLogProvider 需要在启动时覆盖'));
