/// 「2 小时前」这样的相对时间：书架上「继续阅读」那本书上次读的时间。
String relativeTime(DateTime time, DateTime now) {
  final elapsed = now.difference(time);
  if (elapsed.inMinutes < 1) return '刚刚';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes} 分钟前';
  final today = DateTime(now.year, now.month, now.day);
  if (!time.isBefore(today)) return '${elapsed.inHours} 小时前';
  final days = today.difference(DateTime(time.year, time.month, time.day)).inDays;
  if (days == 1) return '昨天';
  if (days < 7) return '$days 天前';
  return '${time.month} 月 ${time.day} 日';
}
