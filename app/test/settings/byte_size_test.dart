import 'package:flutter_test/flutter_test.dart';
import 'package:lanmao_reader/settings/byte_size.dart';

void main() {
  test('1024 进位：不足 1KB 显示整数字节，其余一位小数', () {
    expect(formatByteSize(0), '0 B');
    expect(formatByteSize(1023), '1023 B');
    expect(formatByteSize(1024), '1.0 KB');
    expect(formatByteSize(1536 * 1024), '1.5 MB');
    expect(formatByteSize(3 * 1024 * 1024 * 1024), '3.0 GB');
    expect(formatByteSize(2048 * 1024 * 1024 * 1024), '2048.0 GB');
  });
}
