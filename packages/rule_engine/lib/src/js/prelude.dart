/// 书源 JS 运行时的预置 JS，每个引擎创建时执行一次（见 `SourceJs`）。
///
/// - 宿主函数只有一个 `__host.call(api, args)`，这里把它包装成三种 `java` 对象、`cookie`、`cache`、
///   `source`、`book`、`chapter` 和元素、响应、加密器的包装类；同名 API 在 Dart 侧按当前求值帧分发。
/// - 跨边界的值都是 JSON。Dart 侧的对象用带标记的 JSON 对象表示：`\u0000h` 是句柄（元素、响应、加密器），
///   `\u0000e` 是元素列表，`\u0000o` 是宿主对象（`java`、`cookie`、`cache`、`source`、`book`、`chapter`），
///   `\u0000n` 是 JSON 表示不了的数字（NaN、Infinity），`\u0000s` 是 Java Map 的 `toString` 文本。`revive` 把它们换成包装对象，包装对象的 `toJSON`
///   再变回标记，所以交回 Dart 时能还原。
/// - 宿主交给 JS 的数组补上不可枚举的 `toArray`、`size`、`get`、`isEmpty`，和 Java 列表的写法兼容。
library;

const String sourceJsPrelude = r'''
(function (G) {
  'use strict';
  var hostCall = G.__host.call;
  delete G.__host;
  var H = '\u0000h', E = '\u0000e', O = '\u0000o', N = '\u0000n', S = '\u0000s';
  var slice = Array.prototype.slice;

  function hidden(target, name, value) {
    Object.defineProperty(target, name, { value: value, writable: true, configurable: true });
  }

  // 宿主返回 null（Dart 侧的 null 在 C 侧是 undefined）时给 JS null，与 MD3 里 Kotlin 的 null 一致
  function call(api, args) {
    var value = hostCall(api, args);
    return value === undefined ? null : revive(value);
  }

  function method(api) {
    return function () { return call(api, slice.call(arguments)); };
  }

  // ---------------------------------------------------------------- 列表

  function listify(array) {
    hidden(array, 'toArray', function () { return listify(slice.call(this)); });
    hidden(array, 'size', function () { return this.length; });
    hidden(array, 'get', function (i) { return this[i]; });
    hidden(array, 'isEmpty', function () { return this.length === 0; });
    return array;
  }

  // ---------------------------------------------------------------- 元素

  function JsElement(id) { hidden(this, H, id); }
  ['text', 'ownText', 'html', 'outerHtml', 'data', 'attr', 'hasAttr', 'hasClass', 'id', 'tagName', 'select',
    'selectFirst', 'children', 'parent', 'parentNode', 'getAllElements', 'remove'].forEach(function (name) {
    hidden(JsElement.prototype, name, function () {
      return call('el.' + name, [this[H]].concat(slice.call(arguments)));
    });
  });
  hidden(JsElement.prototype, 'toString', function () { return this.outerHtml(); });
  hidden(JsElement.prototype, 'toJSON', function () {
    var tag = {}; tag[H] = this[H]; tag.t = 'el'; return tag;
  });

  function ids(list) {
    return list.map(function (el) { return el[H]; });
  }

  function elements(idList) {
    var list = listify(idList.map(function (id) { return new JsElement(id); }));
    ['text', 'html', 'attr', 'select', 'eq', 'first', 'last', 'outerHtml', 'hasClass', 'hasAttr', 'eachText', 'eachAttr']
      .forEach(function (name) {
      hidden(list, name, function () { return call('els.' + name, [ids(this)].concat(slice.call(arguments))); });
    });
    // jsoup Elements.remove()：不带参数时从文档里删掉这些元素；带参数时是 Java 列表的 remove(下标) 或 remove(元素)
    hidden(list, 'remove', function (item) {
      if (arguments.length === 0) {
        call('els.remove', [ids(this)]);
        return this;
      }
      if (typeof item === 'number') return this.splice(item, 1)[0];
      var at = this.indexOf(item);
      if (at < 0) return false;
      this.splice(at, 1);
      return true;
    });
    // Rhino 里调的是 Java 列表的方法，按 jsoup 的 equals（同一个节点）比较；同一个节点每次交给 JS 是新的包装对象，
    // 所以按句柄编号比（fix-md3-diff-findings 设计 D3）。参数不是元素时按数组原来的方法
    function position(target, from, step) {
      for (var i = from; i >= 0 && i < this.length; i += step) {
        if (this[i] instanceof JsElement && this[i][H] === target[H]) return i;
      }
      return -1;
    }
    hidden(list, 'indexOf', function (item) {
      return item instanceof JsElement ? position.call(this, item, 0, 1) : Array.prototype.indexOf.apply(this, arguments);
    });
    hidden(list, 'lastIndexOf', function (item) {
      return item instanceof JsElement ? position.call(this, item, this.length - 1, -1) : Array.prototype.lastIndexOf.apply(this, arguments);
    });
    hidden(list, 'includes', function (item) { return this.indexOf(item) >= 0; });
    hidden(list, 'contains', function (item) { return this.indexOf(item) >= 0; });
    hidden(list, 'toString', function () { return this.outerHtml(); });
    hidden(list, 'toJSON', function () { var tag = {}; tag[E] = ids(this); return tag; });
    return list;
  }

  // ---------------------------------------------------------------- 响应、加密器

  function JsResponse(id) { hidden(this, H, id); }
  ['body', 'code', 'statusCode', 'message', 'url', 'headers', 'header', 'cookies', 'isSuccessful', 'callTime']
    .forEach(function (name) {
      hidden(JsResponse.prototype, name, function () {
        return call('res.' + name, [this[H]].concat(slice.call(arguments)));
      });
    });
  hidden(JsResponse.prototype, 'raw', function () { return this; });
  hidden(JsResponse.prototype, 'request', function () {
    var self = this;
    return { url: function () { return self.url(); } };
  });
  hidden(JsResponse.prototype, 'toJSON', function () {
    var tag = {}; tag[H] = this[H]; tag.t = 'res'; return tag;
  });

  function JsCipher(id) { hidden(this, H, id); }
  ['encrypt', 'encryptBase64', 'encryptHex', 'encryptStr', 'decrypt', 'decryptStr', 'decryptHex', 'decryptBase64']
    .forEach(function (name) {
      hidden(JsCipher.prototype, name, function () {
        return call('cipher.' + name, [this[H]].concat(slice.call(arguments)));
      });
    });
  hidden(JsCipher.prototype, 'setIv', function (iv) { call('cipher.setIv', [this[H], iv]); return this; });
  hidden(JsCipher.prototype, 'toJSON', function () {
    var tag = {}; tag[H] = this[H]; tag.t = 'cipher'; return tag;
  });

  var handleTypes = { el: JsElement, res: JsResponse, cipher: JsCipher };

  // ---------------------------------------------------------------- java、cookie、cache、source

  // 三种 java 对象和书源对象都有的方法（MD3 的 JsExtensions）；java 的 put、get 语义按上下文不同，书源对象的另行覆盖
  var common = ['ajax', 'ajaxAll', 'connect', 'post', 'head', 'put', 'get', 'getCookie', 'log', 'logType',
    'toast', 'longToast', 'base64Decode', 'base64DecodeToByteArray', 'base64Encode', 'hexDecodeToString',
    'hexDecodeToByteArray', 'hexEncodeToString', 'strToBytes', 'bytesToStr', 'encodeURI', 'md5Encode',
    'md5Encode16', 'digestHex', 'digestBase64Str', 'HMacHex', 'HMacBase64', 'createSymmetricCrypto',
    'aesDecodeToByteArray', 'aesDecodeToString', 'aesBase64DecodeToByteArray', 'aesBase64DecodeToString',
    'aesDecodeArgsBase64Str', 'aesEncodeToByteArray', 'aesEncodeToString', 'aesEncodeToBase64ByteArray',
    'aesEncodeToBase64String', 'aesEncodeArgsBase64Str', 'desDecodeToString', 'desBase64DecodeToString',
    'desEncodeToString', 'desEncodeToBase64String', 'tripleDESDecodeStr', 'tripleDESDecodeArgsBase64Str',
    'tripleDESEncodeBase64Str', 'tripleDESEncodeArgsBase64Str', 'timeFormat', 'timeFormatUTC', 'toNumChapter',
    'htmlFormat', 'randomUUID', 'getWebViewUA', 'androidId'];
  // 不支持的宿主 API：调用时以「不支持的宿主 API」结束，JS 的 try/catch 拦不住
  var unsupported = ['startBrowser', 'startBrowserAwait', 'getVerificationCode', 'openUrl', 'webView',
    'webViewGetSource', 'webViewGetOverrideUrl', 'getReadBookConfig',
    'getReadBookConfigMap', 'getThemeMode', 'getThemeConfig', 'getThemeConfigMap', 'downloadFile', 'cacheFile',
    'importScript', 'getFile', 'readFile', 'readTxtFile', 'deleteFile', 'unzipFile', 'un7zFile', 'unrarFile',
    'unArchiveFile', 'getTxtInFolder', 'getZipStringContent', 'getRarStringContent', 'get7zStringContent',
    'getZipByteArrayContent', 'getRarByteArrayContent', 'get7zByteArrayContent', 'queryTTF', 'queryBase64TTF',
    'replaceFont', 't2s', 's2t', 'createAsymmetricCrypto', 'createSign', 'refreshExplore'];

  // ---------------------------------------------------------------- Java 包（add-rhino-compat 设计 D1、D3）

  // Rhino 的 Java 包：已知的路径返回实现，其余任何属性都是下一层包，调用或 new 时按 missingClass 结束
  var javaPackages = new WeakMap();
  // 包里用普通函数实现的类 → 短类名，供 importClass 取名（fix-explore-compat 设计 D1）
  var javaClassNames = new WeakMap();
  function javaPackage(path, known, isClass) {
    var proxy = new Proxy(function () {}, {
      get: function (target, name) {
        if (typeof name !== 'string') return undefined;
        if (known && Object.prototype.hasOwnProperty.call(known, name)) return known[name];
        return javaPackage(path + '.' + name, null);
      },
      apply: function () { missingClass(path); },
      construct: function () { missingClass(path); }
    });
    javaPackages.set(proxy, { path: path, known: known, isClass: !!isClass });
    if (known && !isClass) {
      Object.keys(known).forEach(function (name) {
        var value = known[name];
        if (typeof value === 'function' && !javaPackages.has(value)) javaClassNames.set(value, name);
      });
    }
    return proxy;
  }

  // MD3 运行时带的包根（设计 D2）：这些包下没实现的类是我们的能力缺口，以拦不住的「不支持的宿主 API」结束；
  // 其它包根在 MD3 里也没有，和 Rhino 调用不存在的类一样是可以捕获的 TypeError
  var md3PackageRoot = /^(java|javax|android|androidx|dalvik|kotlin|kotlinx|okhttp3|okio|cn\.hutool|me\.ag2s|io\.legado|org\.(apache|jsoup|json|mozilla|w3c|xml)|com\.(google|jayway|script))(\.|$)/;
  function missingClass(path) {
    if (md3PackageRoot.test(path.replace(/^Packages\./, ''))) hostCall('unsupported', [path]);
    throw new TypeError(path + ' 不是 Java 类');
  }

  // with 只解析已导入的类；普通变量和原生全局仍沿原作用域查找。
  function JavaImporter() {
    var packages = [];
    var classes = Object.create(null);
    var target = Object.create(null);
    hidden(target, 'importPackage', function () {
      for (var i = 0; i < arguments.length; i++) {
        var info = javaPackages.get(arguments[i]);
        if (!info || info.isClass) throw new TypeError('importPackage 需要 Java 包');
        if (!info.known) hostCall('unsupported', [info.path]);
        if (packages.indexOf(info) < 0) packages.push(info);
      }
    });
    // 按短类名登记；没实现的路径（无法区分类和包）当成类，调用或 new 时才结束（设计 D1）
    hidden(target, 'importClass', function () {
      for (var i = 0; i < arguments.length; i++) {
        var info = javaPackages.get(arguments[i]);
        var name = info ? (info.isClass || !info.known ? info.path.split('.').pop() : null) : javaClassNames.get(arguments[i]);
        if (!name) throw new TypeError('importClass 需要 Java 类');
        classes[name] = arguments[i];
      }
    });
    // 显式导入的类优先于导入的包
    function lookup(name) {
      if (typeof name !== 'string') return undefined;
      if (name in classes) return classes[name];
      var found;
      packages.forEach(function (pkg) {
        if (!Object.prototype.hasOwnProperty.call(pkg.known, name)) return;
        var value = pkg.known[name];
        var info = javaPackages.get(value);
        if (info && !info.isClass) return;
        if (found !== undefined && found !== value) {
          var previous = javaPackages.get(found);
          if (!previous || !info || previous.path.replace(/^Packages\./, '') !== info.path.replace(/^Packages\./, '')) {
            throw new TypeError('Java 导入类名冲突：' + name);
          }
        }
        found = value;
      });
      return found;
    }
    target.importPackage.apply(target, arguments);
    return new Proxy(target, {
      has: function (target, name) { return Object.prototype.hasOwnProperty.call(target, name) || lookup(name) !== undefined; },
      get: function (target, name) {
        if (name === Symbol.unscopables) return undefined;
        return Object.prototype.hasOwnProperty.call(target, name) ? target[name] : lookup(name);
      }
    });
  }

  // 只包装显式构造的 Java String，不修改原生 String 或宿主 API 返回的字符串。
  function JavaString(value, charset) {
    if (!(this instanceof JavaString)) return new JavaString(...arguments);
    var text;
    if (arguments.length === 0) text = '';
    else if (Array.isArray(value)) {
      if (arguments.length > 2 || (arguments.length === 2 && charset == null)) throw new TypeError('不支持的 String 构造参数');
      text = call('bytesToStr', [value, arguments.length < 2 ? 'UTF-8' : charset]);
    } else {
      if (value == null || arguments.length !== 1) throw new TypeError('不支持的 String 构造参数');
      text = String(value);
    }
    hidden(this, 'toString', function () { return text; });
    hidden(this, 'toJSON', function () { return text; });
    hidden(this, 'getBytes', function (charset) {
      if (arguments.length > 1 || (arguments.length === 1 && charset == null)) throw new TypeError('不支持的 getBytes 参数');
      return call('strToBytes', [text, arguments.length === 0 ? 'UTF-8' : charset]);
    });
  }

  function messageDigest(algorithm) {
    if (arguments.length !== 1) throw new TypeError('不支持的 MessageDigest.getInstance 参数');
    // 创建时即验证算法；摘要状态留在 JS 实例里，jsLib 缓存跨任务使用时不会持有失效的任务句柄。
    var size = call('javaClass.digest', [algorithm, []]).length;
    var bytes = [];
    return {
      update: function (input, offset, length) {
        if (arguments.length === 1 && typeof input === 'number') bytes.push((input << 24) >> 24);
        else {
          if (!Array.isArray(input) || (arguments.length !== 1 && arguments.length !== 3)) {
            throw new TypeError('不支持的 MessageDigest.update 参数');
          }
          var start = arguments.length === 1 ? 0 : Math.trunc(Number(offset));
          var count = arguments.length === 1 ? input.length : Math.trunc(Number(length));
          if (!Number.isFinite(start) || !Number.isFinite(count) || start < 0 || count < 0 || start + count > input.length) {
            throw new RangeError('MessageDigest.update 字节范围越界');
          }
          for (var i = start; i < start + count; i++) bytes.push((input[i] << 24) >> 24);
        }
      },
      digest: function (input) {
        if (arguments.length > 1 || (arguments.length === 1 && !Array.isArray(input))) {
          throw new TypeError('不支持的 MessageDigest.digest 参数');
        }
        if (arguments.length === 1) this.update(input);
        var result = call('javaClass.digest', [algorithm, bytes]);
        bytes = [];
        return result;
      },
      reset: function () { bytes = []; },
      getDigestLength: function () { return size; }
    };
  }

  // 有限的内存流/列表兼容：状态在 JS 对象内，jsLib 缓存对象时不依赖任务句柄。
  function javaInt(value) {
    var number = Math.trunc(Number(value));
    if (!Number.isFinite(number) || number < -2147483648 || number > 2147483647) {
      throw new RangeError('超出 Java int 范围');
    }
    return number;
  }

  function checkCapacity(args) {
    if (args.length > 1 || (args.length === 1 && typeof args[0] !== 'number')) {
      throw new TypeError('只支持无参数或初始容量构造');
    }
    if (args.length === 1 && javaInt(args[0]) < 0) throw new RangeError('初始容量不能为负');
  }

  function ByteArrayOutputStream(capacity) {
    if (!(this instanceof ByteArrayOutputStream)) return new ByteArrayOutputStream(...arguments);
    checkCapacity(arguments);
    var bytes = [];
    hidden(this, 'write', function (input, offset, length) {
      if (arguments.length === 1 && typeof input === 'number') {
        bytes.push((javaInt(input) << 24) >> 24);
        return;
      }
      if (!Array.isArray(input) || (arguments.length !== 1 && arguments.length !== 3)) {
        throw new TypeError('不支持的 ByteArrayOutputStream.write 参数');
      }
      var start = arguments.length === 1 ? 0 : javaInt(offset);
      var count = arguments.length === 1 ? input.length : javaInt(length);
      if (start < 0 || count < 0 || start + count > input.length) throw new RangeError('写入字节范围越界');
      // 先复制和转换全部输入，参数错误不会留下半次写入。
      var copied = input.slice(start, start + count).map(function (b) { return (javaInt(b) << 24) >> 24; });
      for (var i = 0; i < copied.length; i++) bytes.push(copied[i]);
    });
    hidden(this, 'toByteArray', function () { return listify(bytes.slice()); });
    hidden(this, 'size', function () { return bytes.length; });
    hidden(this, 'reset', function () { bytes = []; });
    // JDK 的 ByteArrayOutputStream.close 无副作用，之后仍可以写入。
    hidden(this, 'close', function () {});
  }

  function ArrayList(capacity) {
    if (!(this instanceof ArrayList)) return new ArrayList(...arguments);
    checkCapacity(arguments);
    var values = [];
    hidden(this, 'add', function (value) {
      if (arguments.length !== 1) throw new TypeError('只支持 ArrayList.add(值)');
      values.push(value);
      return true;
    });
    hidden(this, 'get', function (index) {
      if (arguments.length !== 1) throw new TypeError('只支持 ArrayList.get(下标)');
      var at = javaInt(index);
      if (at < 0 || at >= values.length) throw new RangeError('列表下标越界');
      return values[at];
    });
    hidden(this, 'size', function () { return values.length; });
    hidden(this, 'isEmpty', function () { return values.length === 0; });
    hidden(this, 'clear', function () { values = []; });
    hidden(this, 'toArray', function () {
      if (arguments.length !== 0) throw new TypeError('只支持 ArrayList.toArray()');
      return listify(values.slice());
    });
    // 保留元素对象；跨宿主边界复用数组/JsObject 转换，搜索与目录仍能按对象字段取值。
    hidden(this, 'toJSON', function () { return values.slice(); });
  }

  function copyBytes(input) {
    if (!Array.isArray(input)) throw new TypeError('需要字节数组');
    return input.map(function (b) { return (javaInt(b) << 24) >> 24; });
  }

  function copyOfRange(input, from, to) {
    if (arguments.length !== 3) throw new TypeError('只支持 Arrays.copyOfRange(bytes, from, to)');
    var bytes = copyBytes(input), start = javaInt(from), end = javaInt(to);
    if (start < 0 || start > bytes.length || end < start) throw new RangeError('字节范围越界');
    var result = new Array(end - start).fill(0);
    for (var i = start; i < Math.min(end, bytes.length); i++) result[i - start] = bytes[i];
    return listify(result);
  }

  var secretKeys = new WeakMap(), ivSpecs = new WeakMap();
  function SecretKeySpec(bytes, algorithm) {
    if (!(this instanceof SecretKeySpec)) return new SecretKeySpec(...arguments);
    if (arguments.length !== 2 || algorithm == null) throw new TypeError('不支持的 SecretKeySpec 构造参数');
    var key = copyBytes(bytes), name = String(algorithm);
    if (!key.length) throw new TypeError('Empty key');
    secretKeys.set(this, { bytes: key, algorithm: name });
    hidden(this, 'getEncoded', function () { return listify(key.slice()); });
    hidden(this, 'getAlgorithm', function () { return name; });
    hidden(this, 'getFormat', function () { return 'RAW'; });
  }
  function IvParameterSpec(bytes) {
    if (!(this instanceof IvParameterSpec)) return new IvParameterSpec(...arguments);
    if (arguments.length !== 1) throw new TypeError('不支持的 IvParameterSpec 构造参数');
    var iv = copyBytes(bytes);
    ivSpecs.set(this, iv);
    hidden(this, 'getIV', function () { return listify(iv.slice()); });
  }
  function aesCipher(transformation) {
    if (arguments.length !== 1 || transformation == null) throw new TypeError('不支持的 Cipher.getInstance 参数');
    var name = String(transformation), normalized = name.toUpperCase();
    if (normalized === 'AES') normalized = 'AES/ECB/PKCS5PADDING';
    if (!/^AES\/(CBC|ECB)\/(PKCS5PADDING|PKCS7PADDING|NOPADDING)$/.test(normalized)) {
      throw new TypeError('不支持的 Cipher 变换：' + name);
    }
    var cbc = normalized.split('/')[1] === 'CBC', state = null;
    return {
      init: function (mode, keySpec, ivSpec) {
        state = null;
        if (arguments.length !== 2 && arguments.length !== 3) throw new TypeError('不支持的 Cipher.init 参数');
        mode = javaInt(mode);
        if (mode !== 1 && mode !== 2) throw new TypeError('只支持 Cipher 加密或解密');
        var key = secretKeys.get(keySpec), iv = ivSpec == null ? null : ivSpecs.get(ivSpec);
        if (!key || key.algorithm.toUpperCase() !== 'AES' || [16, 24, 32].indexOf(key.bytes.length) < 0) {
          throw new TypeError('Invalid AES key');
        }
        if (ivSpec != null && !iv) throw new TypeError('需要 IvParameterSpec');
        if (!cbc && iv !== null) throw new TypeError('ECB mode cannot use IV');
        if (cbc && iv === null) {
          if (mode === 2) throw new TypeError('Parameters missing');
          iv = call('javaClass.randomIv', []);
        }
        if (cbc && iv.length !== 16) throw new TypeError('Wrong IV length: must be 16 bytes long');
        state = { mode: mode, key: key.bytes.slice(), iv: iv === null ? null : iv.slice() };
      },
      doFinal: function (input) {
        if (!state) throw new TypeError('Cipher not initialized');
        if (arguments.length > 1) throw new TypeError('只支持 Cipher.doFinal(bytes)');
        var bytes = arguments.length === 0 ? [] : copyBytes(input);
        return call('javaClass.cipher', [normalized, state.key, state.iv, state.mode, bytes]);
      },
      getIV: function () { return state && state.iv !== null ? listify(state.iv.slice()) : null; },
      getAlgorithm: function () { return name; },
      getBlockSize: function () { return 16; }
    };
  }
  var Base64 = javaPackage('java.util.Base64', {
    getDecoder: function () {
      if (arguments.length) throw new TypeError('不支持的 Base64.getDecoder 参数');
      return { decode: function (input) {
        if (arguments.length !== 1 || input == null) throw new TypeError('不支持的 Base64.decode 参数');
        var text = Array.isArray(input) ? call('bytesToStr', [copyBytes(input), 'ISO-8859-1']) : String(input);
        return call('javaClass.base64Decode', [text]);
      } };
    }
  }, true);
  var Arrays = javaPackage('java.util.Arrays', { copyOfRange: copyOfRange }, true);
  var Cipher = javaPackage('javax.crypto.Cipher', {
    getInstance: aesCipher, ENCRYPT_MODE: 1, DECRYPT_MODE: 2
  }, true);
  var javax = javaPackage('javax', {
    crypto: javaPackage('javax.crypto', {
      Cipher: Cipher,
      spec: javaPackage('javax.crypto.spec', { SecretKeySpec: SecretKeySpec, IvParameterSpec: IvParameterSpec })
    })
  });

  var pkcs8Specs = new WeakMap(), rsaPrivateKeys = new WeakMap();
  function PKCS8EncodedKeySpec(encoded) {
    if (!(this instanceof PKCS8EncodedKeySpec)) return new PKCS8EncodedKeySpec(...arguments);
    if (arguments.length !== 1) throw new TypeError('不支持的 PKCS8EncodedKeySpec 构造参数');
    var bytes = copyBytes(encoded);
    pkcs8Specs.set(this, bytes);
    hidden(this, 'getEncoded', function () { return listify(bytes.slice()); });
    hidden(this, 'getFormat', function () { return 'PKCS#8'; });
  }
  function rsaKeyFactory(algorithm) {
    if (arguments.length !== 1 || String(algorithm).toUpperCase() !== 'RSA') {
      throw new TypeError('只支持 KeyFactory.getInstance("RSA")');
    }
    var name = String(algorithm);
    return {
      getAlgorithm: function () { return name; },
      generatePrivate: function (spec) {
        if (arguments.length !== 1 || !pkcs8Specs.has(spec)) throw new TypeError('需要 PKCS8EncodedKeySpec');
        // 在生成密钥时解析验证，返回的字节保存在 JS 内，跨任务不依赖宿主句柄。
        var encoded = call('javaClass.rsaPrivateKey', [pkcs8Specs.get(spec)]);
        var key = {};
        rsaPrivateKeys.set(key, encoded);
        hidden(key, 'getEncoded', function () { return listify(encoded.slice()); });
        hidden(key, 'getAlgorithm', function () { return 'RSA'; });
        hidden(key, 'getFormat', function () { return 'PKCS#8'; });
        return key;
      }
    };
  }
  function rsaSignature(algorithm) {
    if (arguments.length !== 1 || String(algorithm).toUpperCase() !== 'SHA256WITHRSA') {
      throw new TypeError('只支持 Signature.getInstance("SHA256WithRSA")');
    }
    var name = String(algorithm), key = null, bytes = [];
    return {
      getAlgorithm: function () { return name; },
      initSign: function (privateKey) {
        key = null;
        bytes = [];
        if (arguments.length !== 1 || !rsaPrivateKeys.has(privateKey)) throw new TypeError('需要 RSA 私钥');
        key = rsaPrivateKeys.get(privateKey);
      },
      update: function (input, offset, length) {
        if (key === null) throw new TypeError('Signature not initialized');
        var copied;
        if (arguments.length === 1 && typeof input === 'number') copied = [(javaInt(input) << 24) >> 24];
        else {
          if (!Array.isArray(input) || (arguments.length !== 1 && arguments.length !== 3)) {
            throw new TypeError('不支持的 Signature.update 参数');
          }
          var start = arguments.length === 1 ? 0 : javaInt(offset);
          var count = arguments.length === 1 ? input.length : javaInt(length);
          if (start < 0 || count < 0 || start + count > input.length) throw new RangeError('Signature.update 字节范围越界');
          copied = copyBytes(input.slice(start, start + count));
        }
        for (var i = 0; i < copied.length; i++) bytes.push(copied[i]);
      },
      sign: function () {
        if (key === null) throw new TypeError('Signature not initialized');
        if (arguments.length !== 0) throw new TypeError('只支持 Signature.sign()');
        var result = call('javaClass.rsaSign', [key, bytes]);
        bytes = [];
        return result;
      }
    };
  }
  var KeyFactory = javaPackage('java.security.KeyFactory', { getInstance: rsaKeyFactory }, true);
  var Signature = javaPackage('java.security.Signature', { getInstance: rsaSignature }, true);

  function javaRoot(path) {
    return javaPackage(path, {
      lang: javaPackage(path + '.lang', { String: JavaString }),
      security: javaPackage(path + '.security', {
        MessageDigest: javaPackage(path + '.security.MessageDigest', { getInstance: messageDigest }, true),
        KeyFactory: KeyFactory, Signature: Signature,
        spec: javaPackage(path + '.security.spec', { PKCS8EncodedKeySpec: PKCS8EncodedKeySpec })
      }),
      io: javaPackage(path + '.io', { ByteArrayOutputStream: ByteArrayOutputStream }),
      util: javaPackage(path + '.util', { ArrayList: ArrayList, Base64: Base64, Arrays: Arrays })
    });
  }

  var org = javaPackage('org', {
    jsoup: javaPackage('org.jsoup', {
      Jsoup: javaPackage('org.jsoup.Jsoup', {
        parse: method('jsoup.parse'),
        parseBodyFragment: method('jsoup.parseBodyFragment')
      }, true),
      parser: javaPackage('org.jsoup.parser', {
        Parser: javaPackage('org.jsoup.parser.Parser', {
          unescapeEntities: function (text, inAttribute) {
            if (arguments.length !== 2) throw new TypeError('不支持的 Parser.unescapeEntities 参数');
            return call('jsoup.unescapeEntities', [text, !!inAttribute]);
          }
        }, true)
      })
    })
  });
  function strResponse(url, body) {
    if (arguments.length !== 2) throw new TypeError('不支持的 StrResponse 构造参数');
    return call('res.create', [url, body]);
  }
  var io = javaPackage('Packages.io', {
    legado: javaPackage('Packages.io.legado', {
      app: javaPackage('Packages.io.legado.app', {
        help: javaPackage('Packages.io.legado.app.help', {
          http: javaPackage('Packages.io.legado.app.help.http', { StrResponse: strResponse })
        })
      })
    })
  });
  // 宿主全局：jsLib 的代码和变量层的 this 上也能用（Rhino 的顶层作用域就有它们）
  // jsLib 的词法作用域里 java 是包；规则/URL/书源变量层注入的 java 仍然是各自的宿主对象。
  __qjs.setGlobals({ java: javaRoot('java'), javax: javax, JavaImporter: JavaImporter, org: org,
    Packages: javaPackage('Packages', { org: org, java: javaRoot('Packages.java'), javax: javax, io: io }) });

  function javaObject(own, owner) {
    var target = {};
    common.concat(own).forEach(function (name) { hidden(target, name, method(name)); });
    unsupported.forEach(function (name) {
      hidden(target, name, function () { hostCall('unsupported', [owner + '.' + name]); });
    });
    return target;
  }

  var ruleJava = javaObject(['getString', 'getStringList', 'getElement', 'getElements', 'setContent'], 'java');
  ['reGetBook', 'refreshTocUrl'].forEach(function (name) {
    hidden(ruleJava, name, function () { hostCall('unsupported', ['java.' + name]); });
  });

  var urlJava = javaObject(['getStrResponse', 'initUrl'], 'java');
  var headerMap = {};
  ['put', 'get', 'remove', 'containsKey', 'putAll'].forEach(function (name) {
    hidden(headerMap, name, method('headerMap.' + name));
  });
  hidden(urlJava, 'headerMap', headerMap);
  // AnalyzeUrl 的公开属性，Rhino 当成属性读：当前请求的地址、处理过的地址规则；只读，赋值被忽略
  ['url', 'ruleUrl'].forEach(function (name) {
    Object.defineProperty(urlJava, name, { get: method('urlJava.' + name), configurable: true });
  });

  var cookie = {};
  ['getCookie', 'getKey', 'setCookie', 'replaceCookie', 'removeCookie', 'cookieToMap', 'mapToCookie']
    .forEach(function (name) { hidden(cookie, name, method('cookie.' + name)); });

  var cache = {};
  ['put', 'get', 'delete', 'putFile', 'getFile', 'putMemory', 'getFromMemory', 'deleteMemory']
    .forEach(function (name) { hidden(cache, name, method('cache.' + name)); });

  // 书源对象：字段只读（赋值被忽略），方法是 MD3 BaseSource 的方法加上 JsExtensions 的方法。
  // put、get 是 BaseSource 的书源级变量，不随上下文变。
  // 同一个任务里的求值共用一个对象，字段在第一次见到它时向宿主取一次。
  var sourceMethods = ['put', 'get', 'getKey', 'getTag', 'getVariable', 'setVariable', 'putVariable', 'getLoginHeader',
    'getLoginHeaderMap', 'putLoginHeader', 'removeLoginHeader', 'getLoginInfo', 'getLoginInfoMap', 'putLoginInfo',
    'removeLoginInfo'];
  var lastSource = null;

  function sourceObject(tag) {
    if (lastSource !== null && lastSource.id === tag.id) return lastSource.object;
    var target = javaObject([], 'source');
    sourceMethods.forEach(function (name) { hidden(target, name, method('source.' + name)); });
    readOnly(target, hostCall('source.fields', []));
    hidden(target, 'toJSON', function () { var t = {}; t[O] = 'source'; return t; });
    lastSource = { id: tag.id, object: target };
    return target;
  }

  function readOnly(target, fields) {
    Object.keys(fields).forEach(function (key) {
      var value = revive(fields[key]);
      Object.defineProperty(target, key, { get: function () { return value; }, enumerable: true });
    });
  }

  // 书籍：字段赋值写回 Dart 侧的书籍
  function bookObject(fields) {
    var target = {};
    Object.keys(fields).forEach(function (key) {
      var value = fields[key];
      Object.defineProperty(target, key, {
        get: function () { return value; },
        set: function (v) { call('book.set', [key, v]); value = v; },
        enumerable: true
      });
    });
    ['getVariable', 'putVariable', 'setReverseToc', 'upCustomIntro', 'getCustomVariable', 'putCustomVariable']
      .forEach(function (name) { hidden(target, name, method('book.' + name)); });
    hidden(target, 'toJSON', function () { var t = {}; t[O] = 'book'; return t; });
    return target;
  }

  // 章节：字段只读（赋值被忽略）
  function chapterObject(fields) {
    var target = {};
    readOnly(target, fields);
    ['getVariable', 'putVariable'].forEach(function (name) { hidden(target, name, method('chapter.' + name)); });
    hidden(target, 'toJSON', function () { var t = {}; t[O] = 'chapter'; return t; });
    return target;
  }

  function hostObject(tag) {
    switch (tag[O]) {
      case 'ruleJava': return ruleJava;
      case 'urlJava': return urlJava;
      case 'cookie': return cookie;
      case 'cache': return cache;
      case 'source': return sourceObject(tag);
      case 'book': return bookObject(tag.v);
      case 'chapter': return chapterObject(tag.v);
    }
    throw new Error('未知的宿主对象：' + tag[O]);
  }

  // ---------------------------------------------------------------- 标记与包装对象互换

  function revive(value) {
    if (value === null || typeof value !== 'object') return value;
    if (Array.isArray(value)) {
      for (var i = 0; i < value.length; i++) value[i] = revive(value[i]);
      return listify(value);
    }
    if (H in value) return new handleTypes[value.t](value[H]);
    if (E in value) return elements(value[E]);
    if (O in value) return hostObject(value);
    if (N in value) return Number(value[N]);
    if (S in value) {
      // Java Map：toString 是 Java 的格式（{k=v, …}），可以用 get(键) 取值
      var text = value[S];
      delete value[S];
      hidden(value, 'toString', function () { return text; });
      if (!('get' in value)) hidden(value, 'get', function (key) { var v = this[key]; return v === undefined ? null : v; });
    }
    for (var key in value) value[key] = revive(value[key]);
    return value;
  }

  __qjs.revive = function (vars) {
    for (var key in vars) vars[key] = revive(vars[key]);
    return vars;
  };

  __qjs.replacer = function (key, value) {
    if (typeof value === 'number' && !isFinite(value)) {
      var tag = {}; tag[N] = String(value); return tag;
    }
    return value;
  };
})(globalThis);
''';
