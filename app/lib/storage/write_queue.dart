/// 串行的落盘队列：书源级状态和 Cookie 的写入先在内存里生效，再按写入顺序在这里落盘（设计 D4）。
///
/// 一次写入失败只交给 [onError]，不影响后面的写入。
final class WriteQueue {
  WriteQueue({required this.onError});

  final void Function(Object error) onError;
  Future<void> _tail = Future.value();

  void add(Future<void> Function() write) {
    _tail = _tail.then((_) => write()).catchError((Object error) => onError(error));
  }

  /// 等已加入的写入全部完成（进入后台时调用）。
  Future<void> flush() => _tail;
}
