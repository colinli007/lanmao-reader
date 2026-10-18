import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/database.dart';
import 'content_source.dart';

/// 启动时打开的数据库，在 main 里覆盖（测试里换成内存数据库）。
final databaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError('databaseProvider 需要在启动时覆盖'));

/// 书架和阅读器取目录、正文的来源，在 main 里覆盖（社区版是书源模块的实现）。
final contentSourceProvider = Provider<BookContentSource>((ref) => throw UnimplementedError('contentSourceProvider 需要在启动时覆盖'));
