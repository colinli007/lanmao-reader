# 编码、摘要、加解密、日期格式的用例，见 run_codec.py。字节数组参数用小写十六进制。
def h(text, charset='utf-8'):
    return text.encode(charset).hex()


CASES = []


def add(op, args, note):
    CASES.append((op, args, note))


# 宽松 Base64（Hutool，先去空白）
for s, note in [
    ('5LiJ5L2T', '标准'),
    ('5LiJ5L2T\n', '结尾换行'),
    (' 5LiJ\r\n5L2T\t', '中间空白'),
    ('5LiJ5L2', '缺一个等号'),
    ('5LiJ5L', '缺两个等号'),
    ('YQ', '两个字符'),
    ('YQ=', '一个等号'),
    ('YQ==', '两个等号'),
    ('YQ===', '多余等号'),
    ('Y', '单个字符'),
    ('', '空串'),
    ('====', '只有等号'),
    ('-_-_', 'URL 安全字符'),
    ('+/+/', '标准字符'),
    ('a-b_c+d/', '两种字符混用'),
    ('YQ==YWJj', '中间有填充'),
    ('5LiJ5L2T!!', '结尾非法字符'),
    ('5L*iJ5L2T', '中间非法字符'),
    ('5LiJ5L2T5LiJ5L2T5LiJ5L2T5LiJ5L2T5LiJ5L2T5LiJ5L2T5LiJ5L2T5LiJ5L2T5LiJ5L2T5LiJ5L2T5LiJ5L2T5LiJ5L2T5LiJ5L2T', '长输入'),
]:
    add('base64Lenient', [s], note)

# Android Base64 解码：DEFAULT=0, NO_PADDING=1, NO_WRAP=2, CRLF=4, URL_SAFE=8, NO_CLOSE=16
for s, flags, note in [
    ('5LiJ5L2T', 0, '标准'),
    ('5LiJ5L2T\n', 0, '结尾换行'),
    (' 5LiJ\r\n5L2T\t', 0, '中间空白'),
    ('5LiJ5L2', 0, '缺等号'),
    ('YQ', 0, '两个字符不带等号'),
    ('YQ=', 0, '一个等号'),
    ('YQ==', 0, '两个等号'),
    ('YQ===', 0, '多余等号'),
    ('Y', 0, '单个字符'),
    ('', 0, '空串'),
    ('-_-_', 0, 'URL 安全字符但没有 URL_SAFE'),
    ('-_-_', 8, 'URL_SAFE'),
    ('+/+/', 8, 'URL_SAFE 下的标准字符'),
    ('YQ==YWJj', 0, '中间有填充'),
    ('5LiJ5L2T!!', 0, '非法字符'),
    ('5LiJ5L2T', 2, 'NO_WRAP 对解码无影响'),
    ('YQ', 1, 'NO_PADDING'),
]:
    add('base64Decode', [s, flags], note)

long_bytes = bytes(range(100)).hex()
for data, flags, note in [
    (h('三体'), 0, 'DEFAULT 带结尾换行'),
    (h('三体'), 2, 'NO_WRAP'),
    (h('a'), 1, 'NO_PADDING'),
    (h('a'), 3, 'NO_PADDING | NO_WRAP'),
    (bytes([0xfb, 0xff, 0xfe]).hex(), 8 | 2, 'URL_SAFE | NO_WRAP'),
    (bytes([0xfb, 0xff, 0xfe]).hex(), 2, '同样字节的标准字符'),
    (long_bytes, 0, 'DEFAULT 每 76 个字符换行'),
    (long_bytes, 4, 'CRLF'),
    (long_bytes, 2, '长输入 NO_WRAP'),
    ('', 0, '空'),
    ('', 2, '空 NO_WRAP'),
]:
    add('base64Encode', [data, flags], note)

# 字符集
for text, charset, note in [
    ('三体', 'UTF-8', 'UTF-8'),
    ('三体', 'GBK', 'GBK'),
    ('三体', 'GB2312', 'GB2312'),
    ('𠀀a', 'GB18030', 'GB18030 四字节'),
    ('𠀀a', 'GBK', 'GBK 无法表示的字符'),
    ('é三', 'ISO-8859-1', 'ISO-8859-1 无法表示的字符'),
    ('€', 'GBK', 'GBK 里的欧元符号'),
]:
    add('strToBytes', [text, charset], note)
for data, charset, note in [
    ('e4b889e4bd93', 'UTF-8', 'UTF-8'),
    ('c8fdcce5', 'GBK', 'GBK'),
    ('c8fdcce5', 'GB2312', 'GB2312'),
    ('ff41', 'UTF-8', '非法 UTF-8'),
    ('e4b8', 'UTF-8', '截断的 UTF-8'),
    ('c8', 'GBK', '截断的 GBK'),
    ('e9', 'ISO-8859-1', 'ISO-8859-1'),
    ('9532823341', 'GB18030', 'GB18030 四字节'),
]:
    add('bytesToStr', [data, charset], note)

# 表单编码
for text, charset, note in [
    ('a b+三', 'UTF-8', '空格和加号'),
    ("~!*'()-_.", 'UTF-8', '保留字符'),
    ('&=?/#%:;,@$', 'UTF-8', '分隔符'),
    ('三体', 'GBK', 'GBK'),
    ('三体', 'GB2312', 'GB2312'),
    ('𠀀', 'GB18030', 'GB18030'),
    ('𠀀', 'UTF-8', '代理对'),
    ('三é', 'ISO-8859-1', 'ISO-8859-1 无法表示的字符'),
    ('x', 'BAD-CHARSET', '不认识的字符集'),
    ('', 'UTF-8', '空串'),
    ('A1z\u0000\n', 'UTF-8', '控制字符'),
]:
    add('encodeURI', [text, charset], note)

# 摘要与 HMAC
for alg in ['MD5', 'SHA-1', 'SHA-224', 'SHA-256', 'SHA-384', 'SHA-512']:
    add('digest', [alg, ''], alg + ' 空串')
    add('digest', [alg, '三体abc'], alg)
for alg in ['HmacMD5', 'HmacSHA1', 'HmacSHA224', 'HmacSHA256', 'HmacSHA384', 'HmacSHA512', 'hmacsha256']:
    add('hmac', [alg, 'key', '三体abc'], alg)
add('hmac', ['HmacSHA256', 'k' * 200, 'data'], '超过块长的密钥')
add('hmac', ['HmacSHA256', '', 'data'], '空密钥')

# 对称加解密：变换、密钥、IV、方向、数据
k16, k24, k32 = h('1234567890123456'), h('123456789012345678901234'), h('12345678901234567890123456789012')
iv16, iv8 = h('abcdefghijklmnop'), h('abcdefgh')
text = h('三体：地球往事')
for transformation, key, iv, data, note in [
    ('AES', k16, '', text, '只有算法名按 ECB/PKCS5Padding'),
    ('AES', k16, '', h('三体'), 'AES 默认 ECB（规格场景）'),
    ('AES/ECB/PKCS5Padding', k16, '', text, 'AES-128 ECB'),
    ('AES/ECB/PKCS5Padding', k24, '', text, 'AES-192 ECB'),
    ('AES/ECB/PKCS5Padding', k32, '', text, 'AES-256 ECB'),
    ('AES/ECB/PKCS5Padding', k16, iv16, text, 'ECB 忽略 IV'),
    ('AES/ECB/PKCS7Padding', k16, '', text, 'PKCS7Padding 视同 PKCS5Padding'),
    ('aes/ecb/pkcs5padding', k16, '', text, '小写变换'),
    ('AES/CBC/PKCS5Padding', k16, iv16, text, 'AES CBC'),
    ('AES/CBC/PKCS5Padding', k32, iv16, '', 'CBC 空明文'),
    ('AES/ECB/PKCS5Padding', k16, '', h('0123456789abcdef'), '整块明文多一块填充'),
    ('AES/ECB/NoPadding', k16, '', h('0123456789abcdef'), 'NoPadding 整块'),
    ('AES/CBC/NoPadding', k16, iv16, h('0123456789abcdef0123456789abcdef'), 'CBC NoPadding 两块'),
    ('AES/ECB/NoPadding', k16, '', h('abc'), 'NoPadding 不足一块'),
    ('AES/CBC/PKCS5Padding', k16, iv8, text, 'IV 长度不对'),
    ('AES', h('123456789012345'), '', text, 'AES 密钥 15 字节'),
    ('AES', h('12345678901234567890'), '', text, 'AES 密钥 20 字节'),
    ('DES', h('12345678'), '', text, 'DES ECB'),
    ('DES', h('1234567890abc'), '', text, 'DES 密钥截到 8 字节'),
    ('DES', h('1234567'), '', text, 'DES 密钥不足 8 字节'),
    ('DES/CBC/PKCS5Padding', h('12345678'), iv8, text, 'DES CBC'),
    ('DES/ECB/NoPadding', h('12345678'), '', h('abcdefgh'), 'DES NoPadding'),
    ('DESede', k24, '', text, 'DESede ECB'),
    ('DESede/CBC/PKCS5Padding', k24, iv8, text, 'DESede CBC'),
    ('DESede', k16, '', text, 'DESede 两段密钥'),
    ('DESede', h('123456789012345678901234567890'), '', text, 'DESede 密钥截到 24 字节'),
    ('DESede', h('12345678901234567890'), '', text, 'DESede 密钥 20 字节'),
]:
    add('cipher', [transformation, key, iv, 'encrypt', data], '加密：' + note)
for transformation, key, iv, data, note in [
    ('AES', k16, '', '00' * 16, '填充错误'),
    ('AES', k16, '', '00' * 15, '长度不是块的整数倍'),
    ('AES', k16, '', '', '空密文'),
    ('AES/CBC/PKCS5Padding', k16, '', '00' * 16, 'CBC 没有 IV'),
    ('AES/ECB/NoPadding', k16, '', '00' * 16, 'NoPadding 解密'),
    ('DES', h('12345678'), '', '00' * 8, 'DES 填充错误'),
]:
    add('cipher', [transformation, key, iv, 'decrypt', data], '解密：' + note)

# 日期格式：毫秒、格式、偏移（毫秒）
T = 1700000000123  # 2023-11-14T22:13:20.123Z，星期二
for ms, fmt, offset, note in [
    (0, 'yyyy-MM-dd HH:mm', 28800000, '东八区'),
    (T, 'yyyy-MM-dd HH:mm:ss', 0, 'UTC'),
    (T, 'yyyy-MM-dd HH:mm:ss', 28800000, '跨日'),
    (T, 'yyyy-MM-dd HH:mm:ss', -18000000, '负偏移'),
    (T, 'yyyy-MM-dd HH:mm', 12, '偏移只有 12 毫秒'),
    (T, "yyyy-MM-dd'T'HH:mm:ss.SSSZ", 28800000, 'ISO 风格'),
    (T, 'yy/M/d H:m:s', 0, '短格式'),
    (T, 'yyyyy y', 0, '年份位数'),
    (T, 'h:mm a', 0, '十二小时制下午'),
    (T, 'h:mm a', 7200000, '十二小时制凌晨'),
    (1699920000000, 'hh:mm a', 0, '零点是 12'),
    (T, 'E EE EEE EEEE', 0, '星期'),
    (T, 'M MM MMM MMMM', 0, '月份'),
    (T, 'S SS SSS SSSS', 0, '毫秒'),
    (T, 'Z ZZ', 19800000, '半小时时区'),
    (T, "'at' HH 'o''clock' ''", 0, '单引号转义'),
    (T, 'yyyy年MM月dd日', 28800000, '中文字面量'),
    (-1, 'yyyy-MM-dd HH:mm:ss.SSS', 0, '负时间'),
    (4102444800000, 'yyyy-MM-dd', 0, '2100 年'),
    (T, 'yyyy-MM-dd q', 0, '非法字母'),
]:
    add('timeFormatUTC', [ms, fmt, offset], note)
