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
    'htmlFormat', 'randomUUID', 'getWebViewUA'];
  // 不支持的宿主 API：调用时以「不支持的宿主 API」结束，JS 的 try/catch 拦不住
  var unsupported = ['startBrowser', 'startBrowserAwait', 'getVerificationCode', 'openUrl', 'webView',
    'webViewGetSource', 'webViewGetOverrideUrl', 'androidId', 'getReadBookConfig',
    'getReadBookConfigMap', 'getThemeMode', 'getThemeConfig', 'getThemeConfigMap', 'downloadFile', 'cacheFile',
    'importScript', 'getFile', 'readFile', 'readTxtFile', 'deleteFile', 'unzipFile', 'un7zFile', 'unrarFile',
    'unArchiveFile', 'getTxtInFolder', 'getZipStringContent', 'getRarStringContent', 'get7zStringContent',
    'getZipByteArrayContent', 'getRarByteArrayContent', 'get7zByteArrayContent', 'queryTTF', 'queryBase64TTF',
    'replaceFont', 't2s', 's2t', 'createAsymmetricCrypto', 'createSign', 'refreshExplore'];

  // ---------------------------------------------------------------- Java 包（add-rhino-compat 设计 D1、D3）

  // Rhino 的 Java 包：已知的路径返回实现，其余任何属性都是下一层包，调用或 new 时以「不支持的宿主 API：类名」结束
  function javaPackage(path, known) {
    return new Proxy(function () {}, {
      get: function (target, name) {
        if (typeof name !== 'string') return undefined;
        if (known && Object.prototype.hasOwnProperty.call(known, name)) return known[name];
        return javaPackage(path + '.' + name, null);
      },
      apply: function () { hostCall('unsupported', [path]); },
      construct: function () { hostCall('unsupported', [path]); }
    });
  }

  var org = javaPackage('org', {
    jsoup: javaPackage('org.jsoup', {
      Jsoup: javaPackage('org.jsoup.Jsoup', {
        parse: method('jsoup.parse'),
        parseBodyFragment: method('jsoup.parseBodyFragment')
      })
    })
  });
  // 宿主全局：jsLib 的代码和变量层的 this 上也能用（Rhino 的顶层作用域就有它们）
  __qjs.setGlobals({ org: org, Packages: javaPackage('Packages', { org: org }) });

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
