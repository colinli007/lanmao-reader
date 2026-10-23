const _units = ['KB', 'MB', 'GB'];

/// 字节数的显示（settings「正文缓存大小」）：1024 进位，不足 1KB 显示整数字节，其余保留一位小数。
String formatByteSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < _units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(1)} ${_units[unit]}';
}
