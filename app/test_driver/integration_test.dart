// profile 构建跑集成测试用（flutter test 不支持 --profile）：
//   flutter drive --profile --driver=test_driver/integration_test.dart --target=integration_test/<文件> -d <设备>
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
