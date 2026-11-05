import 'package:rule_engine/src/js/rhino_syntax.dart';
import 'package:test/test.dart';

// source-js「Rhino 专有写法」：解构箭头函数加括号，其余不动
void main() {
  test('数组字面量后面紧跟 => 时加括号', () {
    expect(rhinoCompatible('list.map([t,id]=>t+id)'), 'list.map(([t,id])=>t+id)');
    expect(rhinoCompatible('a.map(([t, id]) => t)'), 'a.map(([t, id]) => t)');
    expect(rhinoCompatible('x = [a, [b, c]] \n => a'), 'x = ([a, [b, c]]) \n => a');
    expect(rhinoCompatible('f([a]=>1, [b]=>2)'), 'f(([a])=>1, ([b])=>2)');
    expect(rhinoCompatible('return [a,b]=>a'), 'return ([a,b])=>a');
  });

  test('下标访问不是解构参数', () {
    // 不是合法的 JS，只检查不会被当成数组字面量
    expect(rhinoCompatible('a[0]=>1'), 'a[0]=>1');
    expect(rhinoCompatible('f()[0] => 1'), 'f()[0] => 1');
  });

  test('字符串、模板、注释、正则里的不动', () {
    for (final code in [
      '"[a]=>" + 1',
      "'[a]=>'",
      '`[a]=>`',
      '// [a]=>\n1',
      '/* [a]=> */ 1',
      r'/\[a\]=>/.test(x)',
      'x.replace(/[a]=>/g, "")',
    ]) {
      expect(rhinoCompatible(code), code, reason: code);
    }
  });

  test('模板字符串里的表达式照常改写', () {
    expect(rhinoCompatible(r'`${list.map([a]=>a)}` + "]=>"'), r'`${list.map(([a])=>a)}` + "]=>"');
  });

  test('除号不当成正则的开头', () {
    expect(rhinoCompatible('var r = a / 2; x.map([k]=>k)'), 'var r = a / 2; x.map(([k])=>k)');
    expect(rhinoCompatible('var r = (a) / [2][0]; x.map([k]=>k)'), 'var r = (a) / [2][0]; x.map(([k])=>k)');
  });

  test('没有 ]=> 时原样返回', () {
    const code = 'var a = [1, 2].map(x => x)';
    expect(identical(rhinoCompatible(code), code), isTrue);
  });
}
