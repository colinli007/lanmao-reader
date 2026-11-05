// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $SourcesTable extends Sources with TableInfo<$SourcesTable, SourceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SourcesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [url, json, enabled, position];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sources';
  @override
  VerificationContext validateIntegrity(
    Insertable<SourceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    } else if (isInserting) {
      context.missing(_enabledMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {url};
  @override
  SourceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SourceRow(
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
    );
  }

  @override
  $SourcesTable createAlias(String alias) {
    return $SourcesTable(attachedDatabase, alias);
  }
}

class SourceRow extends DataClass implements Insertable<SourceRow> {
  final String url;
  final String json;
  final bool enabled;

  /// 首次导入的顺序，更新书源时不变。
  final int position;
  const SourceRow({
    required this.url,
    required this.json,
    required this.enabled,
    required this.position,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['url'] = Variable<String>(url);
    map['json'] = Variable<String>(json);
    map['enabled'] = Variable<bool>(enabled);
    map['position'] = Variable<int>(position);
    return map;
  }

  SourcesCompanion toCompanion(bool nullToAbsent) {
    return SourcesCompanion(
      url: Value(url),
      json: Value(json),
      enabled: Value(enabled),
      position: Value(position),
    );
  }

  factory SourceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SourceRow(
      url: serializer.fromJson<String>(json['url']),
      json: serializer.fromJson<String>(json['json']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'url': serializer.toJson<String>(url),
      'json': serializer.toJson<String>(json),
      'enabled': serializer.toJson<bool>(enabled),
      'position': serializer.toJson<int>(position),
    };
  }

  SourceRow copyWith({
    String? url,
    String? json,
    bool? enabled,
    int? position,
  }) => SourceRow(
    url: url ?? this.url,
    json: json ?? this.json,
    enabled: enabled ?? this.enabled,
    position: position ?? this.position,
  );
  SourceRow copyWithCompanion(SourcesCompanion data) {
    return SourceRow(
      url: data.url.present ? data.url.value : this.url,
      json: data.json.present ? data.json.value : this.json,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SourceRow(')
          ..write('url: $url, ')
          ..write('json: $json, ')
          ..write('enabled: $enabled, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(url, json, enabled, position);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SourceRow &&
          other.url == this.url &&
          other.json == this.json &&
          other.enabled == this.enabled &&
          other.position == this.position);
}

class SourcesCompanion extends UpdateCompanion<SourceRow> {
  final Value<String> url;
  final Value<String> json;
  final Value<bool> enabled;
  final Value<int> position;
  final Value<int> rowid;
  const SourcesCompanion({
    this.url = const Value.absent(),
    this.json = const Value.absent(),
    this.enabled = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SourcesCompanion.insert({
    required String url,
    required String json,
    required bool enabled,
    required int position,
    this.rowid = const Value.absent(),
  }) : url = Value(url),
       json = Value(json),
       enabled = Value(enabled),
       position = Value(position);
  static Insertable<SourceRow> custom({
    Expression<String>? url,
    Expression<String>? json,
    Expression<bool>? enabled,
    Expression<int>? position,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (url != null) 'url': url,
      if (json != null) 'json': json,
      if (enabled != null) 'enabled': enabled,
      if (position != null) 'position': position,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SourcesCompanion copyWith({
    Value<String>? url,
    Value<String>? json,
    Value<bool>? enabled,
    Value<int>? position,
    Value<int>? rowid,
  }) {
    return SourcesCompanion(
      url: url ?? this.url,
      json: json ?? this.json,
      enabled: enabled ?? this.enabled,
      position: position ?? this.position,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SourcesCompanion(')
          ..write('url: $url, ')
          ..write('json: $json, ')
          ..write('enabled: $enabled, ')
          ..write('position: $position, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReplaceRulesTable extends ReplaceRules
    with TableInfo<$ReplaceRulesTable, ReplaceRuleRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReplaceRulesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [id, json, enabled];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'replace_rules';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReplaceRuleRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    } else if (isInserting) {
      context.missing(_enabledMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ReplaceRuleRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReplaceRuleRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
    );
  }

  @override
  $ReplaceRulesTable createAlias(String alias) {
    return $ReplaceRulesTable(attachedDatabase, alias);
  }
}

class ReplaceRuleRow extends DataClass implements Insertable<ReplaceRuleRow> {
  final int id;
  final String json;
  final bool enabled;
  const ReplaceRuleRow({
    required this.id,
    required this.json,
    required this.enabled,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['json'] = Variable<String>(json);
    map['enabled'] = Variable<bool>(enabled);
    return map;
  }

  ReplaceRulesCompanion toCompanion(bool nullToAbsent) {
    return ReplaceRulesCompanion(
      id: Value(id),
      json: Value(json),
      enabled: Value(enabled),
    );
  }

  factory ReplaceRuleRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReplaceRuleRow(
      id: serializer.fromJson<int>(json['id']),
      json: serializer.fromJson<String>(json['json']),
      enabled: serializer.fromJson<bool>(json['enabled']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'json': serializer.toJson<String>(json),
      'enabled': serializer.toJson<bool>(enabled),
    };
  }

  ReplaceRuleRow copyWith({int? id, String? json, bool? enabled}) =>
      ReplaceRuleRow(
        id: id ?? this.id,
        json: json ?? this.json,
        enabled: enabled ?? this.enabled,
      );
  ReplaceRuleRow copyWithCompanion(ReplaceRulesCompanion data) {
    return ReplaceRuleRow(
      id: data.id.present ? data.id.value : this.id,
      json: data.json.present ? data.json.value : this.json,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReplaceRuleRow(')
          ..write('id: $id, ')
          ..write('json: $json, ')
          ..write('enabled: $enabled')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, json, enabled);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReplaceRuleRow &&
          other.id == this.id &&
          other.json == this.json &&
          other.enabled == this.enabled);
}

class ReplaceRulesCompanion extends UpdateCompanion<ReplaceRuleRow> {
  final Value<int> id;
  final Value<String> json;
  final Value<bool> enabled;
  const ReplaceRulesCompanion({
    this.id = const Value.absent(),
    this.json = const Value.absent(),
    this.enabled = const Value.absent(),
  });
  ReplaceRulesCompanion.insert({
    this.id = const Value.absent(),
    required String json,
    required bool enabled,
  }) : json = Value(json),
       enabled = Value(enabled);
  static Insertable<ReplaceRuleRow> custom({
    Expression<int>? id,
    Expression<String>? json,
    Expression<bool>? enabled,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (json != null) 'json': json,
      if (enabled != null) 'enabled': enabled,
    });
  }

  ReplaceRulesCompanion copyWith({
    Value<int>? id,
    Value<String>? json,
    Value<bool>? enabled,
  }) {
    return ReplaceRulesCompanion(
      id: id ?? this.id,
      json: json ?? this.json,
      enabled: enabled ?? this.enabled,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReplaceRulesCompanion(')
          ..write('id: $id, ')
          ..write('json: $json, ')
          ..write('enabled: $enabled')
          ..write(')'))
        .toString();
  }
}

class $BooksTable extends Books with TableInfo<$BooksTable, ShelfBook> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BooksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bookUrlMeta = const VerificationMeta(
    'bookUrl',
  );
  @override
  late final GeneratedColumn<String> bookUrl = GeneratedColumn<String>(
    'book_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originMeta = const VerificationMeta('origin');
  @override
  late final GeneratedColumn<String> origin = GeneratedColumn<String>(
    'origin',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originNameMeta = const VerificationMeta(
    'originName',
  );
  @override
  late final GeneratedColumn<String> originName = GeneratedColumn<String>(
    'origin_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authorMeta = const VerificationMeta('author');
  @override
  late final GeneratedColumn<String> author = GeneratedColumn<String>(
    'author',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _coverUrlMeta = const VerificationMeta(
    'coverUrl',
  );
  @override
  late final GeneratedColumn<String> coverUrl = GeneratedColumn<String>(
    'cover_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _introMeta = const VerificationMeta('intro');
  @override
  late final GeneratedColumn<String> intro = GeneratedColumn<String>(
    'intro',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _wordCountMeta = const VerificationMeta(
    'wordCount',
  );
  @override
  late final GeneratedColumn<String> wordCount = GeneratedColumn<String>(
    'word_count',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _latestChapterTitleMeta =
      const VerificationMeta('latestChapterTitle');
  @override
  late final GeneratedColumn<String> latestChapterTitle =
      GeneratedColumn<String>(
        'latest_chapter_title',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _durChapterIndexMeta = const VerificationMeta(
    'durChapterIndex',
  );
  @override
  late final GeneratedColumn<int> durChapterIndex = GeneratedColumn<int>(
    'dur_chapter_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _durChapterUrlMeta = const VerificationMeta(
    'durChapterUrl',
  );
  @override
  late final GeneratedColumn<String> durChapterUrl = GeneratedColumn<String>(
    'dur_chapter_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durChapterTitleMeta = const VerificationMeta(
    'durChapterTitle',
  );
  @override
  late final GeneratedColumn<String> durChapterTitle = GeneratedColumn<String>(
    'dur_chapter_title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durChapterPosMeta = const VerificationMeta(
    'durChapterPos',
  );
  @override
  late final GeneratedColumn<int> durChapterPos = GeneratedColumn<int>(
    'dur_chapter_pos',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _inShelfMeta = const VerificationMeta(
    'inShelf',
  );
  @override
  late final GeneratedColumn<bool> inShelf = GeneratedColumn<bool>(
    'in_shelf',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("in_shelf" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastReadAtMeta = const VerificationMeta(
    'lastReadAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastReadAt = GeneratedColumn<DateTime>(
    'last_read_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceDataMeta = const VerificationMeta(
    'sourceData',
  );
  @override
  late final GeneratedColumn<String> sourceData = GeneratedColumn<String>(
    'source_data',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    bookUrl,
    origin,
    originName,
    name,
    author,
    kind,
    coverUrl,
    intro,
    wordCount,
    latestChapterTitle,
    durChapterIndex,
    durChapterUrl,
    durChapterTitle,
    durChapterPos,
    inShelf,
    addedAt,
    lastReadAt,
    sourceData,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'books';
  @override
  VerificationContext validateIntegrity(
    Insertable<ShelfBook> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('book_url')) {
      context.handle(
        _bookUrlMeta,
        bookUrl.isAcceptableOrUnknown(data['book_url']!, _bookUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_bookUrlMeta);
    }
    if (data.containsKey('origin')) {
      context.handle(
        _originMeta,
        origin.isAcceptableOrUnknown(data['origin']!, _originMeta),
      );
    } else if (isInserting) {
      context.missing(_originMeta);
    }
    if (data.containsKey('origin_name')) {
      context.handle(
        _originNameMeta,
        originName.isAcceptableOrUnknown(data['origin_name']!, _originNameMeta),
      );
    } else if (isInserting) {
      context.missing(_originNameMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('author')) {
      context.handle(
        _authorMeta,
        author.isAcceptableOrUnknown(data['author']!, _authorMeta),
      );
    } else if (isInserting) {
      context.missing(_authorMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    }
    if (data.containsKey('cover_url')) {
      context.handle(
        _coverUrlMeta,
        coverUrl.isAcceptableOrUnknown(data['cover_url']!, _coverUrlMeta),
      );
    }
    if (data.containsKey('intro')) {
      context.handle(
        _introMeta,
        intro.isAcceptableOrUnknown(data['intro']!, _introMeta),
      );
    }
    if (data.containsKey('word_count')) {
      context.handle(
        _wordCountMeta,
        wordCount.isAcceptableOrUnknown(data['word_count']!, _wordCountMeta),
      );
    }
    if (data.containsKey('latest_chapter_title')) {
      context.handle(
        _latestChapterTitleMeta,
        latestChapterTitle.isAcceptableOrUnknown(
          data['latest_chapter_title']!,
          _latestChapterTitleMeta,
        ),
      );
    }
    if (data.containsKey('dur_chapter_index')) {
      context.handle(
        _durChapterIndexMeta,
        durChapterIndex.isAcceptableOrUnknown(
          data['dur_chapter_index']!,
          _durChapterIndexMeta,
        ),
      );
    }
    if (data.containsKey('dur_chapter_url')) {
      context.handle(
        _durChapterUrlMeta,
        durChapterUrl.isAcceptableOrUnknown(
          data['dur_chapter_url']!,
          _durChapterUrlMeta,
        ),
      );
    }
    if (data.containsKey('dur_chapter_title')) {
      context.handle(
        _durChapterTitleMeta,
        durChapterTitle.isAcceptableOrUnknown(
          data['dur_chapter_title']!,
          _durChapterTitleMeta,
        ),
      );
    }
    if (data.containsKey('dur_chapter_pos')) {
      context.handle(
        _durChapterPosMeta,
        durChapterPos.isAcceptableOrUnknown(
          data['dur_chapter_pos']!,
          _durChapterPosMeta,
        ),
      );
    }
    if (data.containsKey('in_shelf')) {
      context.handle(
        _inShelfMeta,
        inShelf.isAcceptableOrUnknown(data['in_shelf']!, _inShelfMeta),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    }
    if (data.containsKey('last_read_at')) {
      context.handle(
        _lastReadAtMeta,
        lastReadAt.isAcceptableOrUnknown(
          data['last_read_at']!,
          _lastReadAtMeta,
        ),
      );
    }
    if (data.containsKey('source_data')) {
      context.handle(
        _sourceDataMeta,
        sourceData.isAcceptableOrUnknown(data['source_data']!, _sourceDataMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceDataMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bookUrl};
  @override
  ShelfBook map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ShelfBook(
      bookUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_url'],
      )!,
      origin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin'],
      )!,
      originName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin_name'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      author: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      ),
      coverUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_url'],
      ),
      intro: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}intro'],
      ),
      wordCount: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}word_count'],
      ),
      latestChapterTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}latest_chapter_title'],
      ),
      durChapterIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}dur_chapter_index'],
      )!,
      durChapterUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dur_chapter_url'],
      ),
      durChapterTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dur_chapter_title'],
      ),
      durChapterPos: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}dur_chapter_pos'],
      )!,
      inShelf: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}in_shelf'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      ),
      lastReadAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_read_at'],
      ),
      sourceData: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_data'],
      )!,
    );
  }

  @override
  $BooksTable createAlias(String alias) {
    return $BooksTable(attachedDatabase, alias);
  }
}

class ShelfBook extends DataClass implements Insertable<ShelfBook> {
  final String bookUrl;
  final String origin;
  final String originName;
  final String name;
  final String author;
  final String? kind;
  final String? coverUrl;
  final String? intro;
  final String? wordCount;
  final String? latestChapterTitle;

  /// 阅读进度：当前章节的序号、地址、章节名，章内位置是第一个可见段落在排版后正文里的字符偏移。
  final int durChapterIndex;
  final String? durChapterUrl;
  final String? durChapterTitle;
  final int durChapterPos;
  final bool inShelf;
  final DateTime? addedAt;
  final DateTime? lastReadAt;

  /// 只有书源模块解读的数据（书籍变量、目录地址等），这里不透明地保存。
  final String sourceData;
  const ShelfBook({
    required this.bookUrl,
    required this.origin,
    required this.originName,
    required this.name,
    required this.author,
    this.kind,
    this.coverUrl,
    this.intro,
    this.wordCount,
    this.latestChapterTitle,
    required this.durChapterIndex,
    this.durChapterUrl,
    this.durChapterTitle,
    required this.durChapterPos,
    required this.inShelf,
    this.addedAt,
    this.lastReadAt,
    required this.sourceData,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['book_url'] = Variable<String>(bookUrl);
    map['origin'] = Variable<String>(origin);
    map['origin_name'] = Variable<String>(originName);
    map['name'] = Variable<String>(name);
    map['author'] = Variable<String>(author);
    if (!nullToAbsent || kind != null) {
      map['kind'] = Variable<String>(kind);
    }
    if (!nullToAbsent || coverUrl != null) {
      map['cover_url'] = Variable<String>(coverUrl);
    }
    if (!nullToAbsent || intro != null) {
      map['intro'] = Variable<String>(intro);
    }
    if (!nullToAbsent || wordCount != null) {
      map['word_count'] = Variable<String>(wordCount);
    }
    if (!nullToAbsent || latestChapterTitle != null) {
      map['latest_chapter_title'] = Variable<String>(latestChapterTitle);
    }
    map['dur_chapter_index'] = Variable<int>(durChapterIndex);
    if (!nullToAbsent || durChapterUrl != null) {
      map['dur_chapter_url'] = Variable<String>(durChapterUrl);
    }
    if (!nullToAbsent || durChapterTitle != null) {
      map['dur_chapter_title'] = Variable<String>(durChapterTitle);
    }
    map['dur_chapter_pos'] = Variable<int>(durChapterPos);
    map['in_shelf'] = Variable<bool>(inShelf);
    if (!nullToAbsent || addedAt != null) {
      map['added_at'] = Variable<DateTime>(addedAt);
    }
    if (!nullToAbsent || lastReadAt != null) {
      map['last_read_at'] = Variable<DateTime>(lastReadAt);
    }
    map['source_data'] = Variable<String>(sourceData);
    return map;
  }

  BooksCompanion toCompanion(bool nullToAbsent) {
    return BooksCompanion(
      bookUrl: Value(bookUrl),
      origin: Value(origin),
      originName: Value(originName),
      name: Value(name),
      author: Value(author),
      kind: kind == null && nullToAbsent ? const Value.absent() : Value(kind),
      coverUrl: coverUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(coverUrl),
      intro: intro == null && nullToAbsent
          ? const Value.absent()
          : Value(intro),
      wordCount: wordCount == null && nullToAbsent
          ? const Value.absent()
          : Value(wordCount),
      latestChapterTitle: latestChapterTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(latestChapterTitle),
      durChapterIndex: Value(durChapterIndex),
      durChapterUrl: durChapterUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(durChapterUrl),
      durChapterTitle: durChapterTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(durChapterTitle),
      durChapterPos: Value(durChapterPos),
      inShelf: Value(inShelf),
      addedAt: addedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(addedAt),
      lastReadAt: lastReadAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastReadAt),
      sourceData: Value(sourceData),
    );
  }

  factory ShelfBook.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ShelfBook(
      bookUrl: serializer.fromJson<String>(json['bookUrl']),
      origin: serializer.fromJson<String>(json['origin']),
      originName: serializer.fromJson<String>(json['originName']),
      name: serializer.fromJson<String>(json['name']),
      author: serializer.fromJson<String>(json['author']),
      kind: serializer.fromJson<String?>(json['kind']),
      coverUrl: serializer.fromJson<String?>(json['coverUrl']),
      intro: serializer.fromJson<String?>(json['intro']),
      wordCount: serializer.fromJson<String?>(json['wordCount']),
      latestChapterTitle: serializer.fromJson<String?>(
        json['latestChapterTitle'],
      ),
      durChapterIndex: serializer.fromJson<int>(json['durChapterIndex']),
      durChapterUrl: serializer.fromJson<String?>(json['durChapterUrl']),
      durChapterTitle: serializer.fromJson<String?>(json['durChapterTitle']),
      durChapterPos: serializer.fromJson<int>(json['durChapterPos']),
      inShelf: serializer.fromJson<bool>(json['inShelf']),
      addedAt: serializer.fromJson<DateTime?>(json['addedAt']),
      lastReadAt: serializer.fromJson<DateTime?>(json['lastReadAt']),
      sourceData: serializer.fromJson<String>(json['sourceData']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bookUrl': serializer.toJson<String>(bookUrl),
      'origin': serializer.toJson<String>(origin),
      'originName': serializer.toJson<String>(originName),
      'name': serializer.toJson<String>(name),
      'author': serializer.toJson<String>(author),
      'kind': serializer.toJson<String?>(kind),
      'coverUrl': serializer.toJson<String?>(coverUrl),
      'intro': serializer.toJson<String?>(intro),
      'wordCount': serializer.toJson<String?>(wordCount),
      'latestChapterTitle': serializer.toJson<String?>(latestChapterTitle),
      'durChapterIndex': serializer.toJson<int>(durChapterIndex),
      'durChapterUrl': serializer.toJson<String?>(durChapterUrl),
      'durChapterTitle': serializer.toJson<String?>(durChapterTitle),
      'durChapterPos': serializer.toJson<int>(durChapterPos),
      'inShelf': serializer.toJson<bool>(inShelf),
      'addedAt': serializer.toJson<DateTime?>(addedAt),
      'lastReadAt': serializer.toJson<DateTime?>(lastReadAt),
      'sourceData': serializer.toJson<String>(sourceData),
    };
  }

  ShelfBook copyWith({
    String? bookUrl,
    String? origin,
    String? originName,
    String? name,
    String? author,
    Value<String?> kind = const Value.absent(),
    Value<String?> coverUrl = const Value.absent(),
    Value<String?> intro = const Value.absent(),
    Value<String?> wordCount = const Value.absent(),
    Value<String?> latestChapterTitle = const Value.absent(),
    int? durChapterIndex,
    Value<String?> durChapterUrl = const Value.absent(),
    Value<String?> durChapterTitle = const Value.absent(),
    int? durChapterPos,
    bool? inShelf,
    Value<DateTime?> addedAt = const Value.absent(),
    Value<DateTime?> lastReadAt = const Value.absent(),
    String? sourceData,
  }) => ShelfBook(
    bookUrl: bookUrl ?? this.bookUrl,
    origin: origin ?? this.origin,
    originName: originName ?? this.originName,
    name: name ?? this.name,
    author: author ?? this.author,
    kind: kind.present ? kind.value : this.kind,
    coverUrl: coverUrl.present ? coverUrl.value : this.coverUrl,
    intro: intro.present ? intro.value : this.intro,
    wordCount: wordCount.present ? wordCount.value : this.wordCount,
    latestChapterTitle: latestChapterTitle.present
        ? latestChapterTitle.value
        : this.latestChapterTitle,
    durChapterIndex: durChapterIndex ?? this.durChapterIndex,
    durChapterUrl: durChapterUrl.present
        ? durChapterUrl.value
        : this.durChapterUrl,
    durChapterTitle: durChapterTitle.present
        ? durChapterTitle.value
        : this.durChapterTitle,
    durChapterPos: durChapterPos ?? this.durChapterPos,
    inShelf: inShelf ?? this.inShelf,
    addedAt: addedAt.present ? addedAt.value : this.addedAt,
    lastReadAt: lastReadAt.present ? lastReadAt.value : this.lastReadAt,
    sourceData: sourceData ?? this.sourceData,
  );
  ShelfBook copyWithCompanion(BooksCompanion data) {
    return ShelfBook(
      bookUrl: data.bookUrl.present ? data.bookUrl.value : this.bookUrl,
      origin: data.origin.present ? data.origin.value : this.origin,
      originName: data.originName.present
          ? data.originName.value
          : this.originName,
      name: data.name.present ? data.name.value : this.name,
      author: data.author.present ? data.author.value : this.author,
      kind: data.kind.present ? data.kind.value : this.kind,
      coverUrl: data.coverUrl.present ? data.coverUrl.value : this.coverUrl,
      intro: data.intro.present ? data.intro.value : this.intro,
      wordCount: data.wordCount.present ? data.wordCount.value : this.wordCount,
      latestChapterTitle: data.latestChapterTitle.present
          ? data.latestChapterTitle.value
          : this.latestChapterTitle,
      durChapterIndex: data.durChapterIndex.present
          ? data.durChapterIndex.value
          : this.durChapterIndex,
      durChapterUrl: data.durChapterUrl.present
          ? data.durChapterUrl.value
          : this.durChapterUrl,
      durChapterTitle: data.durChapterTitle.present
          ? data.durChapterTitle.value
          : this.durChapterTitle,
      durChapterPos: data.durChapterPos.present
          ? data.durChapterPos.value
          : this.durChapterPos,
      inShelf: data.inShelf.present ? data.inShelf.value : this.inShelf,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
      lastReadAt: data.lastReadAt.present
          ? data.lastReadAt.value
          : this.lastReadAt,
      sourceData: data.sourceData.present
          ? data.sourceData.value
          : this.sourceData,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ShelfBook(')
          ..write('bookUrl: $bookUrl, ')
          ..write('origin: $origin, ')
          ..write('originName: $originName, ')
          ..write('name: $name, ')
          ..write('author: $author, ')
          ..write('kind: $kind, ')
          ..write('coverUrl: $coverUrl, ')
          ..write('intro: $intro, ')
          ..write('wordCount: $wordCount, ')
          ..write('latestChapterTitle: $latestChapterTitle, ')
          ..write('durChapterIndex: $durChapterIndex, ')
          ..write('durChapterUrl: $durChapterUrl, ')
          ..write('durChapterTitle: $durChapterTitle, ')
          ..write('durChapterPos: $durChapterPos, ')
          ..write('inShelf: $inShelf, ')
          ..write('addedAt: $addedAt, ')
          ..write('lastReadAt: $lastReadAt, ')
          ..write('sourceData: $sourceData')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    bookUrl,
    origin,
    originName,
    name,
    author,
    kind,
    coverUrl,
    intro,
    wordCount,
    latestChapterTitle,
    durChapterIndex,
    durChapterUrl,
    durChapterTitle,
    durChapterPos,
    inShelf,
    addedAt,
    lastReadAt,
    sourceData,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ShelfBook &&
          other.bookUrl == this.bookUrl &&
          other.origin == this.origin &&
          other.originName == this.originName &&
          other.name == this.name &&
          other.author == this.author &&
          other.kind == this.kind &&
          other.coverUrl == this.coverUrl &&
          other.intro == this.intro &&
          other.wordCount == this.wordCount &&
          other.latestChapterTitle == this.latestChapterTitle &&
          other.durChapterIndex == this.durChapterIndex &&
          other.durChapterUrl == this.durChapterUrl &&
          other.durChapterTitle == this.durChapterTitle &&
          other.durChapterPos == this.durChapterPos &&
          other.inShelf == this.inShelf &&
          other.addedAt == this.addedAt &&
          other.lastReadAt == this.lastReadAt &&
          other.sourceData == this.sourceData);
}

class BooksCompanion extends UpdateCompanion<ShelfBook> {
  final Value<String> bookUrl;
  final Value<String> origin;
  final Value<String> originName;
  final Value<String> name;
  final Value<String> author;
  final Value<String?> kind;
  final Value<String?> coverUrl;
  final Value<String?> intro;
  final Value<String?> wordCount;
  final Value<String?> latestChapterTitle;
  final Value<int> durChapterIndex;
  final Value<String?> durChapterUrl;
  final Value<String?> durChapterTitle;
  final Value<int> durChapterPos;
  final Value<bool> inShelf;
  final Value<DateTime?> addedAt;
  final Value<DateTime?> lastReadAt;
  final Value<String> sourceData;
  final Value<int> rowid;
  const BooksCompanion({
    this.bookUrl = const Value.absent(),
    this.origin = const Value.absent(),
    this.originName = const Value.absent(),
    this.name = const Value.absent(),
    this.author = const Value.absent(),
    this.kind = const Value.absent(),
    this.coverUrl = const Value.absent(),
    this.intro = const Value.absent(),
    this.wordCount = const Value.absent(),
    this.latestChapterTitle = const Value.absent(),
    this.durChapterIndex = const Value.absent(),
    this.durChapterUrl = const Value.absent(),
    this.durChapterTitle = const Value.absent(),
    this.durChapterPos = const Value.absent(),
    this.inShelf = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.lastReadAt = const Value.absent(),
    this.sourceData = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BooksCompanion.insert({
    required String bookUrl,
    required String origin,
    required String originName,
    required String name,
    required String author,
    this.kind = const Value.absent(),
    this.coverUrl = const Value.absent(),
    this.intro = const Value.absent(),
    this.wordCount = const Value.absent(),
    this.latestChapterTitle = const Value.absent(),
    this.durChapterIndex = const Value.absent(),
    this.durChapterUrl = const Value.absent(),
    this.durChapterTitle = const Value.absent(),
    this.durChapterPos = const Value.absent(),
    this.inShelf = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.lastReadAt = const Value.absent(),
    required String sourceData,
    this.rowid = const Value.absent(),
  }) : bookUrl = Value(bookUrl),
       origin = Value(origin),
       originName = Value(originName),
       name = Value(name),
       author = Value(author),
       sourceData = Value(sourceData);
  static Insertable<ShelfBook> custom({
    Expression<String>? bookUrl,
    Expression<String>? origin,
    Expression<String>? originName,
    Expression<String>? name,
    Expression<String>? author,
    Expression<String>? kind,
    Expression<String>? coverUrl,
    Expression<String>? intro,
    Expression<String>? wordCount,
    Expression<String>? latestChapterTitle,
    Expression<int>? durChapterIndex,
    Expression<String>? durChapterUrl,
    Expression<String>? durChapterTitle,
    Expression<int>? durChapterPos,
    Expression<bool>? inShelf,
    Expression<DateTime>? addedAt,
    Expression<DateTime>? lastReadAt,
    Expression<String>? sourceData,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bookUrl != null) 'book_url': bookUrl,
      if (origin != null) 'origin': origin,
      if (originName != null) 'origin_name': originName,
      if (name != null) 'name': name,
      if (author != null) 'author': author,
      if (kind != null) 'kind': kind,
      if (coverUrl != null) 'cover_url': coverUrl,
      if (intro != null) 'intro': intro,
      if (wordCount != null) 'word_count': wordCount,
      if (latestChapterTitle != null)
        'latest_chapter_title': latestChapterTitle,
      if (durChapterIndex != null) 'dur_chapter_index': durChapterIndex,
      if (durChapterUrl != null) 'dur_chapter_url': durChapterUrl,
      if (durChapterTitle != null) 'dur_chapter_title': durChapterTitle,
      if (durChapterPos != null) 'dur_chapter_pos': durChapterPos,
      if (inShelf != null) 'in_shelf': inShelf,
      if (addedAt != null) 'added_at': addedAt,
      if (lastReadAt != null) 'last_read_at': lastReadAt,
      if (sourceData != null) 'source_data': sourceData,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BooksCompanion copyWith({
    Value<String>? bookUrl,
    Value<String>? origin,
    Value<String>? originName,
    Value<String>? name,
    Value<String>? author,
    Value<String?>? kind,
    Value<String?>? coverUrl,
    Value<String?>? intro,
    Value<String?>? wordCount,
    Value<String?>? latestChapterTitle,
    Value<int>? durChapterIndex,
    Value<String?>? durChapterUrl,
    Value<String?>? durChapterTitle,
    Value<int>? durChapterPos,
    Value<bool>? inShelf,
    Value<DateTime?>? addedAt,
    Value<DateTime?>? lastReadAt,
    Value<String>? sourceData,
    Value<int>? rowid,
  }) {
    return BooksCompanion(
      bookUrl: bookUrl ?? this.bookUrl,
      origin: origin ?? this.origin,
      originName: originName ?? this.originName,
      name: name ?? this.name,
      author: author ?? this.author,
      kind: kind ?? this.kind,
      coverUrl: coverUrl ?? this.coverUrl,
      intro: intro ?? this.intro,
      wordCount: wordCount ?? this.wordCount,
      latestChapterTitle: latestChapterTitle ?? this.latestChapterTitle,
      durChapterIndex: durChapterIndex ?? this.durChapterIndex,
      durChapterUrl: durChapterUrl ?? this.durChapterUrl,
      durChapterTitle: durChapterTitle ?? this.durChapterTitle,
      durChapterPos: durChapterPos ?? this.durChapterPos,
      inShelf: inShelf ?? this.inShelf,
      addedAt: addedAt ?? this.addedAt,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      sourceData: sourceData ?? this.sourceData,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bookUrl.present) {
      map['book_url'] = Variable<String>(bookUrl.value);
    }
    if (origin.present) {
      map['origin'] = Variable<String>(origin.value);
    }
    if (originName.present) {
      map['origin_name'] = Variable<String>(originName.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (author.present) {
      map['author'] = Variable<String>(author.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (coverUrl.present) {
      map['cover_url'] = Variable<String>(coverUrl.value);
    }
    if (intro.present) {
      map['intro'] = Variable<String>(intro.value);
    }
    if (wordCount.present) {
      map['word_count'] = Variable<String>(wordCount.value);
    }
    if (latestChapterTitle.present) {
      map['latest_chapter_title'] = Variable<String>(latestChapterTitle.value);
    }
    if (durChapterIndex.present) {
      map['dur_chapter_index'] = Variable<int>(durChapterIndex.value);
    }
    if (durChapterUrl.present) {
      map['dur_chapter_url'] = Variable<String>(durChapterUrl.value);
    }
    if (durChapterTitle.present) {
      map['dur_chapter_title'] = Variable<String>(durChapterTitle.value);
    }
    if (durChapterPos.present) {
      map['dur_chapter_pos'] = Variable<int>(durChapterPos.value);
    }
    if (inShelf.present) {
      map['in_shelf'] = Variable<bool>(inShelf.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (lastReadAt.present) {
      map['last_read_at'] = Variable<DateTime>(lastReadAt.value);
    }
    if (sourceData.present) {
      map['source_data'] = Variable<String>(sourceData.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BooksCompanion(')
          ..write('bookUrl: $bookUrl, ')
          ..write('origin: $origin, ')
          ..write('originName: $originName, ')
          ..write('name: $name, ')
          ..write('author: $author, ')
          ..write('kind: $kind, ')
          ..write('coverUrl: $coverUrl, ')
          ..write('intro: $intro, ')
          ..write('wordCount: $wordCount, ')
          ..write('latestChapterTitle: $latestChapterTitle, ')
          ..write('durChapterIndex: $durChapterIndex, ')
          ..write('durChapterUrl: $durChapterUrl, ')
          ..write('durChapterTitle: $durChapterTitle, ')
          ..write('durChapterPos: $durChapterPos, ')
          ..write('inShelf: $inShelf, ')
          ..write('addedAt: $addedAt, ')
          ..write('lastReadAt: $lastReadAt, ')
          ..write('sourceData: $sourceData, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChaptersTable extends Chapters
    with TableInfo<$ChaptersTable, TocChapter> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChaptersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bookUrlMeta = const VerificationMeta(
    'bookUrl',
  );
  @override
  late final GeneratedColumn<String> bookUrl = GeneratedColumn<String>(
    'book_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idxMeta = const VerificationMeta('idx');
  @override
  late final GeneratedColumn<int> idx = GeneratedColumn<int>(
    'idx',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isVolumeMeta = const VerificationMeta(
    'isVolume',
  );
  @override
  late final GeneratedColumn<bool> isVolume = GeneratedColumn<bool>(
    'is_volume',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_volume" IN (0, 1))',
    ),
  );
  static const VerificationMeta _isVipMeta = const VerificationMeta('isVip');
  @override
  late final GeneratedColumn<bool> isVip = GeneratedColumn<bool>(
    'is_vip',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_vip" IN (0, 1))',
    ),
  );
  static const VerificationMeta _isPayMeta = const VerificationMeta('isPay');
  @override
  late final GeneratedColumn<bool> isPay = GeneratedColumn<bool>(
    'is_pay',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_pay" IN (0, 1))',
    ),
  );
  static const VerificationMeta _tagMeta = const VerificationMeta('tag');
  @override
  late final GeneratedColumn<String> tag = GeneratedColumn<String>(
    'tag',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceDataMeta = const VerificationMeta(
    'sourceData',
  );
  @override
  late final GeneratedColumn<String> sourceData = GeneratedColumn<String>(
    'source_data',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    bookUrl,
    idx,
    url,
    title,
    isVolume,
    isVip,
    isPay,
    tag,
    sourceData,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chapters';
  @override
  VerificationContext validateIntegrity(
    Insertable<TocChapter> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('book_url')) {
      context.handle(
        _bookUrlMeta,
        bookUrl.isAcceptableOrUnknown(data['book_url']!, _bookUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_bookUrlMeta);
    }
    if (data.containsKey('idx')) {
      context.handle(
        _idxMeta,
        idx.isAcceptableOrUnknown(data['idx']!, _idxMeta),
      );
    } else if (isInserting) {
      context.missing(_idxMeta);
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('is_volume')) {
      context.handle(
        _isVolumeMeta,
        isVolume.isAcceptableOrUnknown(data['is_volume']!, _isVolumeMeta),
      );
    } else if (isInserting) {
      context.missing(_isVolumeMeta);
    }
    if (data.containsKey('is_vip')) {
      context.handle(
        _isVipMeta,
        isVip.isAcceptableOrUnknown(data['is_vip']!, _isVipMeta),
      );
    } else if (isInserting) {
      context.missing(_isVipMeta);
    }
    if (data.containsKey('is_pay')) {
      context.handle(
        _isPayMeta,
        isPay.isAcceptableOrUnknown(data['is_pay']!, _isPayMeta),
      );
    } else if (isInserting) {
      context.missing(_isPayMeta);
    }
    if (data.containsKey('tag')) {
      context.handle(
        _tagMeta,
        tag.isAcceptableOrUnknown(data['tag']!, _tagMeta),
      );
    }
    if (data.containsKey('source_data')) {
      context.handle(
        _sourceDataMeta,
        sourceData.isAcceptableOrUnknown(data['source_data']!, _sourceDataMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceDataMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bookUrl, idx};
  @override
  TocChapter map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TocChapter(
      bookUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_url'],
      )!,
      idx: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}idx'],
      )!,
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      isVolume: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_volume'],
      )!,
      isVip: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_vip'],
      )!,
      isPay: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_pay'],
      )!,
      tag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tag'],
      ),
      sourceData: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_data'],
      )!,
    );
  }

  @override
  $ChaptersTable createAlias(String alias) {
    return $ChaptersTable(attachedDatabase, alias);
  }
}

class TocChapter extends DataClass implements Insertable<TocChapter> {
  final String bookUrl;
  final int idx;
  final String url;
  final String title;
  final bool isVolume;
  final bool isVip;
  final bool isPay;
  final String? tag;

  /// 只有书源模块解读的数据（章节变量、目录页地址等）。
  final String sourceData;
  const TocChapter({
    required this.bookUrl,
    required this.idx,
    required this.url,
    required this.title,
    required this.isVolume,
    required this.isVip,
    required this.isPay,
    this.tag,
    required this.sourceData,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['book_url'] = Variable<String>(bookUrl);
    map['idx'] = Variable<int>(idx);
    map['url'] = Variable<String>(url);
    map['title'] = Variable<String>(title);
    map['is_volume'] = Variable<bool>(isVolume);
    map['is_vip'] = Variable<bool>(isVip);
    map['is_pay'] = Variable<bool>(isPay);
    if (!nullToAbsent || tag != null) {
      map['tag'] = Variable<String>(tag);
    }
    map['source_data'] = Variable<String>(sourceData);
    return map;
  }

  ChaptersCompanion toCompanion(bool nullToAbsent) {
    return ChaptersCompanion(
      bookUrl: Value(bookUrl),
      idx: Value(idx),
      url: Value(url),
      title: Value(title),
      isVolume: Value(isVolume),
      isVip: Value(isVip),
      isPay: Value(isPay),
      tag: tag == null && nullToAbsent ? const Value.absent() : Value(tag),
      sourceData: Value(sourceData),
    );
  }

  factory TocChapter.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TocChapter(
      bookUrl: serializer.fromJson<String>(json['bookUrl']),
      idx: serializer.fromJson<int>(json['idx']),
      url: serializer.fromJson<String>(json['url']),
      title: serializer.fromJson<String>(json['title']),
      isVolume: serializer.fromJson<bool>(json['isVolume']),
      isVip: serializer.fromJson<bool>(json['isVip']),
      isPay: serializer.fromJson<bool>(json['isPay']),
      tag: serializer.fromJson<String?>(json['tag']),
      sourceData: serializer.fromJson<String>(json['sourceData']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bookUrl': serializer.toJson<String>(bookUrl),
      'idx': serializer.toJson<int>(idx),
      'url': serializer.toJson<String>(url),
      'title': serializer.toJson<String>(title),
      'isVolume': serializer.toJson<bool>(isVolume),
      'isVip': serializer.toJson<bool>(isVip),
      'isPay': serializer.toJson<bool>(isPay),
      'tag': serializer.toJson<String?>(tag),
      'sourceData': serializer.toJson<String>(sourceData),
    };
  }

  TocChapter copyWith({
    String? bookUrl,
    int? idx,
    String? url,
    String? title,
    bool? isVolume,
    bool? isVip,
    bool? isPay,
    Value<String?> tag = const Value.absent(),
    String? sourceData,
  }) => TocChapter(
    bookUrl: bookUrl ?? this.bookUrl,
    idx: idx ?? this.idx,
    url: url ?? this.url,
    title: title ?? this.title,
    isVolume: isVolume ?? this.isVolume,
    isVip: isVip ?? this.isVip,
    isPay: isPay ?? this.isPay,
    tag: tag.present ? tag.value : this.tag,
    sourceData: sourceData ?? this.sourceData,
  );
  TocChapter copyWithCompanion(ChaptersCompanion data) {
    return TocChapter(
      bookUrl: data.bookUrl.present ? data.bookUrl.value : this.bookUrl,
      idx: data.idx.present ? data.idx.value : this.idx,
      url: data.url.present ? data.url.value : this.url,
      title: data.title.present ? data.title.value : this.title,
      isVolume: data.isVolume.present ? data.isVolume.value : this.isVolume,
      isVip: data.isVip.present ? data.isVip.value : this.isVip,
      isPay: data.isPay.present ? data.isPay.value : this.isPay,
      tag: data.tag.present ? data.tag.value : this.tag,
      sourceData: data.sourceData.present
          ? data.sourceData.value
          : this.sourceData,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TocChapter(')
          ..write('bookUrl: $bookUrl, ')
          ..write('idx: $idx, ')
          ..write('url: $url, ')
          ..write('title: $title, ')
          ..write('isVolume: $isVolume, ')
          ..write('isVip: $isVip, ')
          ..write('isPay: $isPay, ')
          ..write('tag: $tag, ')
          ..write('sourceData: $sourceData')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    bookUrl,
    idx,
    url,
    title,
    isVolume,
    isVip,
    isPay,
    tag,
    sourceData,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TocChapter &&
          other.bookUrl == this.bookUrl &&
          other.idx == this.idx &&
          other.url == this.url &&
          other.title == this.title &&
          other.isVolume == this.isVolume &&
          other.isVip == this.isVip &&
          other.isPay == this.isPay &&
          other.tag == this.tag &&
          other.sourceData == this.sourceData);
}

class ChaptersCompanion extends UpdateCompanion<TocChapter> {
  final Value<String> bookUrl;
  final Value<int> idx;
  final Value<String> url;
  final Value<String> title;
  final Value<bool> isVolume;
  final Value<bool> isVip;
  final Value<bool> isPay;
  final Value<String?> tag;
  final Value<String> sourceData;
  final Value<int> rowid;
  const ChaptersCompanion({
    this.bookUrl = const Value.absent(),
    this.idx = const Value.absent(),
    this.url = const Value.absent(),
    this.title = const Value.absent(),
    this.isVolume = const Value.absent(),
    this.isVip = const Value.absent(),
    this.isPay = const Value.absent(),
    this.tag = const Value.absent(),
    this.sourceData = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChaptersCompanion.insert({
    required String bookUrl,
    required int idx,
    required String url,
    required String title,
    required bool isVolume,
    required bool isVip,
    required bool isPay,
    this.tag = const Value.absent(),
    required String sourceData,
    this.rowid = const Value.absent(),
  }) : bookUrl = Value(bookUrl),
       idx = Value(idx),
       url = Value(url),
       title = Value(title),
       isVolume = Value(isVolume),
       isVip = Value(isVip),
       isPay = Value(isPay),
       sourceData = Value(sourceData);
  static Insertable<TocChapter> custom({
    Expression<String>? bookUrl,
    Expression<int>? idx,
    Expression<String>? url,
    Expression<String>? title,
    Expression<bool>? isVolume,
    Expression<bool>? isVip,
    Expression<bool>? isPay,
    Expression<String>? tag,
    Expression<String>? sourceData,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bookUrl != null) 'book_url': bookUrl,
      if (idx != null) 'idx': idx,
      if (url != null) 'url': url,
      if (title != null) 'title': title,
      if (isVolume != null) 'is_volume': isVolume,
      if (isVip != null) 'is_vip': isVip,
      if (isPay != null) 'is_pay': isPay,
      if (tag != null) 'tag': tag,
      if (sourceData != null) 'source_data': sourceData,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChaptersCompanion copyWith({
    Value<String>? bookUrl,
    Value<int>? idx,
    Value<String>? url,
    Value<String>? title,
    Value<bool>? isVolume,
    Value<bool>? isVip,
    Value<bool>? isPay,
    Value<String?>? tag,
    Value<String>? sourceData,
    Value<int>? rowid,
  }) {
    return ChaptersCompanion(
      bookUrl: bookUrl ?? this.bookUrl,
      idx: idx ?? this.idx,
      url: url ?? this.url,
      title: title ?? this.title,
      isVolume: isVolume ?? this.isVolume,
      isVip: isVip ?? this.isVip,
      isPay: isPay ?? this.isPay,
      tag: tag ?? this.tag,
      sourceData: sourceData ?? this.sourceData,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bookUrl.present) {
      map['book_url'] = Variable<String>(bookUrl.value);
    }
    if (idx.present) {
      map['idx'] = Variable<int>(idx.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (isVolume.present) {
      map['is_volume'] = Variable<bool>(isVolume.value);
    }
    if (isVip.present) {
      map['is_vip'] = Variable<bool>(isVip.value);
    }
    if (isPay.present) {
      map['is_pay'] = Variable<bool>(isPay.value);
    }
    if (tag.present) {
      map['tag'] = Variable<String>(tag.value);
    }
    if (sourceData.present) {
      map['source_data'] = Variable<String>(sourceData.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChaptersCompanion(')
          ..write('bookUrl: $bookUrl, ')
          ..write('idx: $idx, ')
          ..write('url: $url, ')
          ..write('title: $title, ')
          ..write('isVolume: $isVolume, ')
          ..write('isVip: $isVip, ')
          ..write('isPay: $isPay, ')
          ..write('tag: $tag, ')
          ..write('sourceData: $sourceData, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ContentsTable extends Contents
    with TableInfo<$ContentsTable, ContentRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ContentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bookUrlMeta = const VerificationMeta(
    'bookUrl',
  );
  @override
  late final GeneratedColumn<String> bookUrl = GeneratedColumn<String>(
    'book_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chapterUrlMeta = const VerificationMeta(
    'chapterUrl',
  );
  @override
  late final GeneratedColumn<String> chapterUrl = GeneratedColumn<String>(
    'chapter_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [bookUrl, chapterUrl, title, content];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'contents';
  @override
  VerificationContext validateIntegrity(
    Insertable<ContentRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('book_url')) {
      context.handle(
        _bookUrlMeta,
        bookUrl.isAcceptableOrUnknown(data['book_url']!, _bookUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_bookUrlMeta);
    }
    if (data.containsKey('chapter_url')) {
      context.handle(
        _chapterUrlMeta,
        chapterUrl.isAcceptableOrUnknown(data['chapter_url']!, _chapterUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_chapterUrlMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bookUrl, chapterUrl};
  @override
  ContentRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ContentRow(
      bookUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_url'],
      )!,
      chapterUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chapter_url'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
    );
  }

  @override
  $ContentsTable createAlias(String alias) {
    return $ContentsTable(attachedDatabase, alias);
  }
}

class ContentRow extends DataClass implements Insertable<ContentRow> {
  final String bookUrl;
  final String chapterUrl;
  final String title;
  final String content;
  const ContentRow({
    required this.bookUrl,
    required this.chapterUrl,
    required this.title,
    required this.content,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['book_url'] = Variable<String>(bookUrl);
    map['chapter_url'] = Variable<String>(chapterUrl);
    map['title'] = Variable<String>(title);
    map['content'] = Variable<String>(content);
    return map;
  }

  ContentsCompanion toCompanion(bool nullToAbsent) {
    return ContentsCompanion(
      bookUrl: Value(bookUrl),
      chapterUrl: Value(chapterUrl),
      title: Value(title),
      content: Value(content),
    );
  }

  factory ContentRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ContentRow(
      bookUrl: serializer.fromJson<String>(json['bookUrl']),
      chapterUrl: serializer.fromJson<String>(json['chapterUrl']),
      title: serializer.fromJson<String>(json['title']),
      content: serializer.fromJson<String>(json['content']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bookUrl': serializer.toJson<String>(bookUrl),
      'chapterUrl': serializer.toJson<String>(chapterUrl),
      'title': serializer.toJson<String>(title),
      'content': serializer.toJson<String>(content),
    };
  }

  ContentRow copyWith({
    String? bookUrl,
    String? chapterUrl,
    String? title,
    String? content,
  }) => ContentRow(
    bookUrl: bookUrl ?? this.bookUrl,
    chapterUrl: chapterUrl ?? this.chapterUrl,
    title: title ?? this.title,
    content: content ?? this.content,
  );
  ContentRow copyWithCompanion(ContentsCompanion data) {
    return ContentRow(
      bookUrl: data.bookUrl.present ? data.bookUrl.value : this.bookUrl,
      chapterUrl: data.chapterUrl.present
          ? data.chapterUrl.value
          : this.chapterUrl,
      title: data.title.present ? data.title.value : this.title,
      content: data.content.present ? data.content.value : this.content,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ContentRow(')
          ..write('bookUrl: $bookUrl, ')
          ..write('chapterUrl: $chapterUrl, ')
          ..write('title: $title, ')
          ..write('content: $content')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(bookUrl, chapterUrl, title, content);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ContentRow &&
          other.bookUrl == this.bookUrl &&
          other.chapterUrl == this.chapterUrl &&
          other.title == this.title &&
          other.content == this.content);
}

class ContentsCompanion extends UpdateCompanion<ContentRow> {
  final Value<String> bookUrl;
  final Value<String> chapterUrl;
  final Value<String> title;
  final Value<String> content;
  final Value<int> rowid;
  const ContentsCompanion({
    this.bookUrl = const Value.absent(),
    this.chapterUrl = const Value.absent(),
    this.title = const Value.absent(),
    this.content = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ContentsCompanion.insert({
    required String bookUrl,
    required String chapterUrl,
    required String title,
    required String content,
    this.rowid = const Value.absent(),
  }) : bookUrl = Value(bookUrl),
       chapterUrl = Value(chapterUrl),
       title = Value(title),
       content = Value(content);
  static Insertable<ContentRow> custom({
    Expression<String>? bookUrl,
    Expression<String>? chapterUrl,
    Expression<String>? title,
    Expression<String>? content,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bookUrl != null) 'book_url': bookUrl,
      if (chapterUrl != null) 'chapter_url': chapterUrl,
      if (title != null) 'title': title,
      if (content != null) 'content': content,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ContentsCompanion copyWith({
    Value<String>? bookUrl,
    Value<String>? chapterUrl,
    Value<String>? title,
    Value<String>? content,
    Value<int>? rowid,
  }) {
    return ContentsCompanion(
      bookUrl: bookUrl ?? this.bookUrl,
      chapterUrl: chapterUrl ?? this.chapterUrl,
      title: title ?? this.title,
      content: content ?? this.content,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bookUrl.present) {
      map['book_url'] = Variable<String>(bookUrl.value);
    }
    if (chapterUrl.present) {
      map['chapter_url'] = Variable<String>(chapterUrl.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ContentsCompanion(')
          ..write('bookUrl: $bookUrl, ')
          ..write('chapterUrl: $chapterUrl, ')
          ..write('title: $title, ')
          ..write('content: $content, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SourceKvTable extends SourceKv
    with TableInfo<$SourceKvTable, SourceKvRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SourceKvTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deadlineMeta = const VerificationMeta(
    'deadline',
  );
  @override
  late final GeneratedColumn<DateTime> deadline = GeneratedColumn<DateTime>(
    'deadline',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value, deadline];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'source_kv';
  @override
  VerificationContext validateIntegrity(
    Insertable<SourceKvRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('deadline')) {
      context.handle(
        _deadlineMeta,
        deadline.isAcceptableOrUnknown(data['deadline']!, _deadlineMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SourceKvRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SourceKvRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      deadline: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deadline'],
      ),
    );
  }

  @override
  $SourceKvTable createAlias(String alias) {
    return $SourceKvTable(attachedDatabase, alias);
  }
}

class SourceKvRow extends DataClass implements Insertable<SourceKvRow> {
  final String key;
  final String value;
  final DateTime? deadline;
  const SourceKvRow({required this.key, required this.value, this.deadline});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    if (!nullToAbsent || deadline != null) {
      map['deadline'] = Variable<DateTime>(deadline);
    }
    return map;
  }

  SourceKvCompanion toCompanion(bool nullToAbsent) {
    return SourceKvCompanion(
      key: Value(key),
      value: Value(value),
      deadline: deadline == null && nullToAbsent
          ? const Value.absent()
          : Value(deadline),
    );
  }

  factory SourceKvRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SourceKvRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      deadline: serializer.fromJson<DateTime?>(json['deadline']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'deadline': serializer.toJson<DateTime?>(deadline),
    };
  }

  SourceKvRow copyWith({
    String? key,
    String? value,
    Value<DateTime?> deadline = const Value.absent(),
  }) => SourceKvRow(
    key: key ?? this.key,
    value: value ?? this.value,
    deadline: deadline.present ? deadline.value : this.deadline,
  );
  SourceKvRow copyWithCompanion(SourceKvCompanion data) {
    return SourceKvRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      deadline: data.deadline.present ? data.deadline.value : this.deadline,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SourceKvRow(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('deadline: $deadline')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, deadline);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SourceKvRow &&
          other.key == this.key &&
          other.value == this.value &&
          other.deadline == this.deadline);
}

class SourceKvCompanion extends UpdateCompanion<SourceKvRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<DateTime?> deadline;
  final Value<int> rowid;
  const SourceKvCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.deadline = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SourceKvCompanion.insert({
    required String key,
    required String value,
    this.deadline = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<SourceKvRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<DateTime>? deadline,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (deadline != null) 'deadline': deadline,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SourceKvCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<DateTime?>? deadline,
    Value<int>? rowid,
  }) {
    return SourceKvCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      deadline: deadline ?? this.deadline,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (deadline.present) {
      map['deadline'] = Variable<DateTime>(deadline.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SourceKvCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('deadline: $deadline, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CookiesTable extends Cookies with TableInfo<$CookiesTable, CookieRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CookiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _domainMeta = const VerificationMeta('domain');
  @override
  late final GeneratedColumn<String> domain = GeneratedColumn<String>(
    'domain',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cookieMeta = const VerificationMeta('cookie');
  @override
  late final GeneratedColumn<String> cookie = GeneratedColumn<String>(
    'cookie',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [domain, cookie];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cookies';
  @override
  VerificationContext validateIntegrity(
    Insertable<CookieRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('domain')) {
      context.handle(
        _domainMeta,
        domain.isAcceptableOrUnknown(data['domain']!, _domainMeta),
      );
    } else if (isInserting) {
      context.missing(_domainMeta);
    }
    if (data.containsKey('cookie')) {
      context.handle(
        _cookieMeta,
        cookie.isAcceptableOrUnknown(data['cookie']!, _cookieMeta),
      );
    } else if (isInserting) {
      context.missing(_cookieMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {domain};
  @override
  CookieRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CookieRow(
      domain: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}domain'],
      )!,
      cookie: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cookie'],
      )!,
    );
  }

  @override
  $CookiesTable createAlias(String alias) {
    return $CookiesTable(attachedDatabase, alias);
  }
}

class CookieRow extends DataClass implements Insertable<CookieRow> {
  final String domain;
  final String cookie;
  const CookieRow({required this.domain, required this.cookie});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['domain'] = Variable<String>(domain);
    map['cookie'] = Variable<String>(cookie);
    return map;
  }

  CookiesCompanion toCompanion(bool nullToAbsent) {
    return CookiesCompanion(domain: Value(domain), cookie: Value(cookie));
  }

  factory CookieRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CookieRow(
      domain: serializer.fromJson<String>(json['domain']),
      cookie: serializer.fromJson<String>(json['cookie']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'domain': serializer.toJson<String>(domain),
      'cookie': serializer.toJson<String>(cookie),
    };
  }

  CookieRow copyWith({String? domain, String? cookie}) =>
      CookieRow(domain: domain ?? this.domain, cookie: cookie ?? this.cookie);
  CookieRow copyWithCompanion(CookiesCompanion data) {
    return CookieRow(
      domain: data.domain.present ? data.domain.value : this.domain,
      cookie: data.cookie.present ? data.cookie.value : this.cookie,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CookieRow(')
          ..write('domain: $domain, ')
          ..write('cookie: $cookie')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(domain, cookie);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CookieRow &&
          other.domain == this.domain &&
          other.cookie == this.cookie);
}

class CookiesCompanion extends UpdateCompanion<CookieRow> {
  final Value<String> domain;
  final Value<String> cookie;
  final Value<int> rowid;
  const CookiesCompanion({
    this.domain = const Value.absent(),
    this.cookie = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CookiesCompanion.insert({
    required String domain,
    required String cookie,
    this.rowid = const Value.absent(),
  }) : domain = Value(domain),
       cookie = Value(cookie);
  static Insertable<CookieRow> custom({
    Expression<String>? domain,
    Expression<String>? cookie,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (domain != null) 'domain': domain,
      if (cookie != null) 'cookie': cookie,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CookiesCompanion copyWith({
    Value<String>? domain,
    Value<String>? cookie,
    Value<int>? rowid,
  }) {
    return CookiesCompanion(
      domain: domain ?? this.domain,
      cookie: cookie ?? this.cookie,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (domain.present) {
      map['domain'] = Variable<String>(domain.value);
    }
    if (cookie.present) {
      map['cookie'] = Variable<String>(cookie.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CookiesCompanion(')
          ..write('domain: $domain, ')
          ..write('cookie: $cookie, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings
    with TableInfo<$SettingsTable, SettingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<SettingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SettingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class SettingRow extends DataClass implements Insertable<SettingRow> {
  final String key;
  final String value;
  const SettingRow({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(key: Value(key), value: Value(value));
  }

  factory SettingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SettingRow copyWith({String? key, String? value}) =>
      SettingRow(key: key ?? this.key, value: value ?? this.value);
  SettingRow copyWithCompanion(SettingsCompanion data) {
    return SettingRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingRow(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingRow &&
          other.key == this.key &&
          other.value == this.value);
}

class SettingsCompanion extends UpdateCompanion<SettingRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<SettingRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SearchKeywordsTable extends SearchKeywords
    with TableInfo<$SearchKeywordsTable, SearchKeywordRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SearchKeywordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _wordMeta = const VerificationMeta('word');
  @override
  late final GeneratedColumn<String> word = GeneratedColumn<String>(
    'word',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usageMeta = const VerificationMeta('usage');
  @override
  late final GeneratedColumn<int> usage = GeneratedColumn<int>(
    'usage',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastUsedMeta = const VerificationMeta(
    'lastUsed',
  );
  @override
  late final GeneratedColumn<DateTime> lastUsed = GeneratedColumn<DateTime>(
    'last_used',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [word, usage, lastUsed];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'search_keywords';
  @override
  VerificationContext validateIntegrity(
    Insertable<SearchKeywordRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('word')) {
      context.handle(
        _wordMeta,
        word.isAcceptableOrUnknown(data['word']!, _wordMeta),
      );
    } else if (isInserting) {
      context.missing(_wordMeta);
    }
    if (data.containsKey('usage')) {
      context.handle(
        _usageMeta,
        usage.isAcceptableOrUnknown(data['usage']!, _usageMeta),
      );
    } else if (isInserting) {
      context.missing(_usageMeta);
    }
    if (data.containsKey('last_used')) {
      context.handle(
        _lastUsedMeta,
        lastUsed.isAcceptableOrUnknown(data['last_used']!, _lastUsedMeta),
      );
    } else if (isInserting) {
      context.missing(_lastUsedMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {word};
  @override
  SearchKeywordRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SearchKeywordRow(
      word: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}word'],
      )!,
      usage: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}usage'],
      )!,
      lastUsed: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_used'],
      )!,
    );
  }

  @override
  $SearchKeywordsTable createAlias(String alias) {
    return $SearchKeywordsTable(attachedDatabase, alias);
  }
}

class SearchKeywordRow extends DataClass
    implements Insertable<SearchKeywordRow> {
  final String word;
  final int usage;
  final DateTime lastUsed;
  const SearchKeywordRow({
    required this.word,
    required this.usage,
    required this.lastUsed,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['word'] = Variable<String>(word);
    map['usage'] = Variable<int>(usage);
    map['last_used'] = Variable<DateTime>(lastUsed);
    return map;
  }

  SearchKeywordsCompanion toCompanion(bool nullToAbsent) {
    return SearchKeywordsCompanion(
      word: Value(word),
      usage: Value(usage),
      lastUsed: Value(lastUsed),
    );
  }

  factory SearchKeywordRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SearchKeywordRow(
      word: serializer.fromJson<String>(json['word']),
      usage: serializer.fromJson<int>(json['usage']),
      lastUsed: serializer.fromJson<DateTime>(json['lastUsed']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'word': serializer.toJson<String>(word),
      'usage': serializer.toJson<int>(usage),
      'lastUsed': serializer.toJson<DateTime>(lastUsed),
    };
  }

  SearchKeywordRow copyWith({String? word, int? usage, DateTime? lastUsed}) =>
      SearchKeywordRow(
        word: word ?? this.word,
        usage: usage ?? this.usage,
        lastUsed: lastUsed ?? this.lastUsed,
      );
  SearchKeywordRow copyWithCompanion(SearchKeywordsCompanion data) {
    return SearchKeywordRow(
      word: data.word.present ? data.word.value : this.word,
      usage: data.usage.present ? data.usage.value : this.usage,
      lastUsed: data.lastUsed.present ? data.lastUsed.value : this.lastUsed,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SearchKeywordRow(')
          ..write('word: $word, ')
          ..write('usage: $usage, ')
          ..write('lastUsed: $lastUsed')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(word, usage, lastUsed);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SearchKeywordRow &&
          other.word == this.word &&
          other.usage == this.usage &&
          other.lastUsed == this.lastUsed);
}

class SearchKeywordsCompanion extends UpdateCompanion<SearchKeywordRow> {
  final Value<String> word;
  final Value<int> usage;
  final Value<DateTime> lastUsed;
  final Value<int> rowid;
  const SearchKeywordsCompanion({
    this.word = const Value.absent(),
    this.usage = const Value.absent(),
    this.lastUsed = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SearchKeywordsCompanion.insert({
    required String word,
    required int usage,
    required DateTime lastUsed,
    this.rowid = const Value.absent(),
  }) : word = Value(word),
       usage = Value(usage),
       lastUsed = Value(lastUsed);
  static Insertable<SearchKeywordRow> custom({
    Expression<String>? word,
    Expression<int>? usage,
    Expression<DateTime>? lastUsed,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (word != null) 'word': word,
      if (usage != null) 'usage': usage,
      if (lastUsed != null) 'last_used': lastUsed,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SearchKeywordsCompanion copyWith({
    Value<String>? word,
    Value<int>? usage,
    Value<DateTime>? lastUsed,
    Value<int>? rowid,
  }) {
    return SearchKeywordsCompanion(
      word: word ?? this.word,
      usage: usage ?? this.usage,
      lastUsed: lastUsed ?? this.lastUsed,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (word.present) {
      map['word'] = Variable<String>(word.value);
    }
    if (usage.present) {
      map['usage'] = Variable<int>(usage.value);
    }
    if (lastUsed.present) {
      map['last_used'] = Variable<DateTime>(lastUsed.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SearchKeywordsCompanion(')
          ..write('word: $word, ')
          ..write('usage: $usage, ')
          ..write('lastUsed: $lastUsed, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedImagesTable extends CachedImages
    with TableInfo<$CachedImagesTable, ContentImageRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedImagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bookUrlMeta = const VerificationMeta(
    'bookUrl',
  );
  @override
  late final GeneratedColumn<String> bookUrl = GeneratedColumn<String>(
    'book_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _srcMeta = const VerificationMeta('src');
  @override
  late final GeneratedColumn<String> src = GeneratedColumn<String>(
    'src',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bytesMeta = const VerificationMeta('bytes');
  @override
  late final GeneratedColumn<Uint8List> bytes = GeneratedColumn<Uint8List>(
    'bytes',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [bookUrl, src, bytes];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'content_images';
  @override
  VerificationContext validateIntegrity(
    Insertable<ContentImageRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('book_url')) {
      context.handle(
        _bookUrlMeta,
        bookUrl.isAcceptableOrUnknown(data['book_url']!, _bookUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_bookUrlMeta);
    }
    if (data.containsKey('src')) {
      context.handle(
        _srcMeta,
        src.isAcceptableOrUnknown(data['src']!, _srcMeta),
      );
    } else if (isInserting) {
      context.missing(_srcMeta);
    }
    if (data.containsKey('bytes')) {
      context.handle(
        _bytesMeta,
        bytes.isAcceptableOrUnknown(data['bytes']!, _bytesMeta),
      );
    } else if (isInserting) {
      context.missing(_bytesMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bookUrl, src};
  @override
  ContentImageRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ContentImageRow(
      bookUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_url'],
      )!,
      src: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}src'],
      )!,
      bytes: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}bytes'],
      )!,
    );
  }

  @override
  $CachedImagesTable createAlias(String alias) {
    return $CachedImagesTable(attachedDatabase, alias);
  }
}

class ContentImageRow extends DataClass implements Insertable<ContentImageRow> {
  final String bookUrl;
  final String src;
  final Uint8List bytes;
  const ContentImageRow({
    required this.bookUrl,
    required this.src,
    required this.bytes,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['book_url'] = Variable<String>(bookUrl);
    map['src'] = Variable<String>(src);
    map['bytes'] = Variable<Uint8List>(bytes);
    return map;
  }

  CachedImagesCompanion toCompanion(bool nullToAbsent) {
    return CachedImagesCompanion(
      bookUrl: Value(bookUrl),
      src: Value(src),
      bytes: Value(bytes),
    );
  }

  factory ContentImageRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ContentImageRow(
      bookUrl: serializer.fromJson<String>(json['bookUrl']),
      src: serializer.fromJson<String>(json['src']),
      bytes: serializer.fromJson<Uint8List>(json['bytes']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bookUrl': serializer.toJson<String>(bookUrl),
      'src': serializer.toJson<String>(src),
      'bytes': serializer.toJson<Uint8List>(bytes),
    };
  }

  ContentImageRow copyWith({String? bookUrl, String? src, Uint8List? bytes}) =>
      ContentImageRow(
        bookUrl: bookUrl ?? this.bookUrl,
        src: src ?? this.src,
        bytes: bytes ?? this.bytes,
      );
  ContentImageRow copyWithCompanion(CachedImagesCompanion data) {
    return ContentImageRow(
      bookUrl: data.bookUrl.present ? data.bookUrl.value : this.bookUrl,
      src: data.src.present ? data.src.value : this.src,
      bytes: data.bytes.present ? data.bytes.value : this.bytes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ContentImageRow(')
          ..write('bookUrl: $bookUrl, ')
          ..write('src: $src, ')
          ..write('bytes: $bytes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(bookUrl, src, $driftBlobEquality.hash(bytes));
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ContentImageRow &&
          other.bookUrl == this.bookUrl &&
          other.src == this.src &&
          $driftBlobEquality.equals(other.bytes, this.bytes));
}

class CachedImagesCompanion extends UpdateCompanion<ContentImageRow> {
  final Value<String> bookUrl;
  final Value<String> src;
  final Value<Uint8List> bytes;
  final Value<int> rowid;
  const CachedImagesCompanion({
    this.bookUrl = const Value.absent(),
    this.src = const Value.absent(),
    this.bytes = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedImagesCompanion.insert({
    required String bookUrl,
    required String src,
    required Uint8List bytes,
    this.rowid = const Value.absent(),
  }) : bookUrl = Value(bookUrl),
       src = Value(src),
       bytes = Value(bytes);
  static Insertable<ContentImageRow> custom({
    Expression<String>? bookUrl,
    Expression<String>? src,
    Expression<Uint8List>? bytes,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bookUrl != null) 'book_url': bookUrl,
      if (src != null) 'src': src,
      if (bytes != null) 'bytes': bytes,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedImagesCompanion copyWith({
    Value<String>? bookUrl,
    Value<String>? src,
    Value<Uint8List>? bytes,
    Value<int>? rowid,
  }) {
    return CachedImagesCompanion(
      bookUrl: bookUrl ?? this.bookUrl,
      src: src ?? this.src,
      bytes: bytes ?? this.bytes,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bookUrl.present) {
      map['book_url'] = Variable<String>(bookUrl.value);
    }
    if (src.present) {
      map['src'] = Variable<String>(src.value);
    }
    if (bytes.present) {
      map['bytes'] = Variable<Uint8List>(bytes.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedImagesCompanion(')
          ..write('bookUrl: $bookUrl, ')
          ..write('src: $src, ')
          ..write('bytes: $bytes, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $SourcesTable sources = $SourcesTable(this);
  late final $ReplaceRulesTable replaceRules = $ReplaceRulesTable(this);
  late final $BooksTable books = $BooksTable(this);
  late final $ChaptersTable chapters = $ChaptersTable(this);
  late final $ContentsTable contents = $ContentsTable(this);
  late final $SourceKvTable sourceKv = $SourceKvTable(this);
  late final $CookiesTable cookies = $CookiesTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final $SearchKeywordsTable searchKeywords = $SearchKeywordsTable(this);
  late final $CachedImagesTable cachedImages = $CachedImagesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    sources,
    replaceRules,
    books,
    chapters,
    contents,
    sourceKv,
    cookies,
    settings,
    searchKeywords,
    cachedImages,
  ];
}

typedef $$SourcesTableCreateCompanionBuilder =
    SourcesCompanion Function({
      required String url,
      required String json,
      required bool enabled,
      required int position,
      Value<int> rowid,
    });
typedef $$SourcesTableUpdateCompanionBuilder =
    SourcesCompanion Function({
      Value<String> url,
      Value<String> json,
      Value<bool> enabled,
      Value<int> position,
      Value<int> rowid,
    });

class $$SourcesTableFilterComposer
    extends Composer<_$AppDatabase, $SourcesTable> {
  $$SourcesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SourcesTableOrderingComposer
    extends Composer<_$AppDatabase, $SourcesTable> {
  $$SourcesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SourcesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SourcesTable> {
  $$SourcesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);
}

class $$SourcesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SourcesTable,
          SourceRow,
          $$SourcesTableFilterComposer,
          $$SourcesTableOrderingComposer,
          $$SourcesTableAnnotationComposer,
          $$SourcesTableCreateCompanionBuilder,
          $$SourcesTableUpdateCompanionBuilder,
          (SourceRow, BaseReferences<_$AppDatabase, $SourcesTable, SourceRow>),
          SourceRow,
          PrefetchHooks Function()
        > {
  $$SourcesTableTableManager(_$AppDatabase db, $SourcesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SourcesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SourcesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SourcesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> url = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SourcesCompanion(
                url: url,
                json: json,
                enabled: enabled,
                position: position,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String url,
                required String json,
                required bool enabled,
                required int position,
                Value<int> rowid = const Value.absent(),
              }) => SourcesCompanion.insert(
                url: url,
                json: json,
                enabled: enabled,
                position: position,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SourcesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SourcesTable,
      SourceRow,
      $$SourcesTableFilterComposer,
      $$SourcesTableOrderingComposer,
      $$SourcesTableAnnotationComposer,
      $$SourcesTableCreateCompanionBuilder,
      $$SourcesTableUpdateCompanionBuilder,
      (SourceRow, BaseReferences<_$AppDatabase, $SourcesTable, SourceRow>),
      SourceRow,
      PrefetchHooks Function()
    >;
typedef $$ReplaceRulesTableCreateCompanionBuilder =
    ReplaceRulesCompanion Function({
      Value<int> id,
      required String json,
      required bool enabled,
    });
typedef $$ReplaceRulesTableUpdateCompanionBuilder =
    ReplaceRulesCompanion Function({
      Value<int> id,
      Value<String> json,
      Value<bool> enabled,
    });

class $$ReplaceRulesTableFilterComposer
    extends Composer<_$AppDatabase, $ReplaceRulesTable> {
  $$ReplaceRulesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReplaceRulesTableOrderingComposer
    extends Composer<_$AppDatabase, $ReplaceRulesTable> {
  $$ReplaceRulesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReplaceRulesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReplaceRulesTable> {
  $$ReplaceRulesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);
}

class $$ReplaceRulesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReplaceRulesTable,
          ReplaceRuleRow,
          $$ReplaceRulesTableFilterComposer,
          $$ReplaceRulesTableOrderingComposer,
          $$ReplaceRulesTableAnnotationComposer,
          $$ReplaceRulesTableCreateCompanionBuilder,
          $$ReplaceRulesTableUpdateCompanionBuilder,
          (
            ReplaceRuleRow,
            BaseReferences<_$AppDatabase, $ReplaceRulesTable, ReplaceRuleRow>,
          ),
          ReplaceRuleRow,
          PrefetchHooks Function()
        > {
  $$ReplaceRulesTableTableManager(_$AppDatabase db, $ReplaceRulesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReplaceRulesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReplaceRulesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReplaceRulesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
              }) => ReplaceRulesCompanion(id: id, json: json, enabled: enabled),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String json,
                required bool enabled,
              }) => ReplaceRulesCompanion.insert(
                id: id,
                json: json,
                enabled: enabled,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReplaceRulesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReplaceRulesTable,
      ReplaceRuleRow,
      $$ReplaceRulesTableFilterComposer,
      $$ReplaceRulesTableOrderingComposer,
      $$ReplaceRulesTableAnnotationComposer,
      $$ReplaceRulesTableCreateCompanionBuilder,
      $$ReplaceRulesTableUpdateCompanionBuilder,
      (
        ReplaceRuleRow,
        BaseReferences<_$AppDatabase, $ReplaceRulesTable, ReplaceRuleRow>,
      ),
      ReplaceRuleRow,
      PrefetchHooks Function()
    >;
typedef $$BooksTableCreateCompanionBuilder =
    BooksCompanion Function({
      required String bookUrl,
      required String origin,
      required String originName,
      required String name,
      required String author,
      Value<String?> kind,
      Value<String?> coverUrl,
      Value<String?> intro,
      Value<String?> wordCount,
      Value<String?> latestChapterTitle,
      Value<int> durChapterIndex,
      Value<String?> durChapterUrl,
      Value<String?> durChapterTitle,
      Value<int> durChapterPos,
      Value<bool> inShelf,
      Value<DateTime?> addedAt,
      Value<DateTime?> lastReadAt,
      required String sourceData,
      Value<int> rowid,
    });
typedef $$BooksTableUpdateCompanionBuilder =
    BooksCompanion Function({
      Value<String> bookUrl,
      Value<String> origin,
      Value<String> originName,
      Value<String> name,
      Value<String> author,
      Value<String?> kind,
      Value<String?> coverUrl,
      Value<String?> intro,
      Value<String?> wordCount,
      Value<String?> latestChapterTitle,
      Value<int> durChapterIndex,
      Value<String?> durChapterUrl,
      Value<String?> durChapterTitle,
      Value<int> durChapterPos,
      Value<bool> inShelf,
      Value<DateTime?> addedAt,
      Value<DateTime?> lastReadAt,
      Value<String> sourceData,
      Value<int> rowid,
    });

class $$BooksTableFilterComposer extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get bookUrl => $composableBuilder(
    column: $table.bookUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originName => $composableBuilder(
    column: $table.originName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverUrl => $composableBuilder(
    column: $table.coverUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get intro => $composableBuilder(
    column: $table.intro,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get wordCount => $composableBuilder(
    column: $table.wordCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get latestChapterTitle => $composableBuilder(
    column: $table.latestChapterTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durChapterIndex => $composableBuilder(
    column: $table.durChapterIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get durChapterUrl => $composableBuilder(
    column: $table.durChapterUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get durChapterTitle => $composableBuilder(
    column: $table.durChapterTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durChapterPos => $composableBuilder(
    column: $table.durChapterPos,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get inShelf => $composableBuilder(
    column: $table.inShelf,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceData => $composableBuilder(
    column: $table.sourceData,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BooksTableOrderingComposer
    extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get bookUrl => $composableBuilder(
    column: $table.bookUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originName => $composableBuilder(
    column: $table.originName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverUrl => $composableBuilder(
    column: $table.coverUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get intro => $composableBuilder(
    column: $table.intro,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get wordCount => $composableBuilder(
    column: $table.wordCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get latestChapterTitle => $composableBuilder(
    column: $table.latestChapterTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durChapterIndex => $composableBuilder(
    column: $table.durChapterIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get durChapterUrl => $composableBuilder(
    column: $table.durChapterUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get durChapterTitle => $composableBuilder(
    column: $table.durChapterTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durChapterPos => $composableBuilder(
    column: $table.durChapterPos,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get inShelf => $composableBuilder(
    column: $table.inShelf,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceData => $composableBuilder(
    column: $table.sourceData,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BooksTableAnnotationComposer
    extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get bookUrl =>
      $composableBuilder(column: $table.bookUrl, builder: (column) => column);

  GeneratedColumn<String> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);

  GeneratedColumn<String> get originName => $composableBuilder(
    column: $table.originName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get author =>
      $composableBuilder(column: $table.author, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get coverUrl =>
      $composableBuilder(column: $table.coverUrl, builder: (column) => column);

  GeneratedColumn<String> get intro =>
      $composableBuilder(column: $table.intro, builder: (column) => column);

  GeneratedColumn<String> get wordCount =>
      $composableBuilder(column: $table.wordCount, builder: (column) => column);

  GeneratedColumn<String> get latestChapterTitle => $composableBuilder(
    column: $table.latestChapterTitle,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durChapterIndex => $composableBuilder(
    column: $table.durChapterIndex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get durChapterUrl => $composableBuilder(
    column: $table.durChapterUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get durChapterTitle => $composableBuilder(
    column: $table.durChapterTitle,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durChapterPos => $composableBuilder(
    column: $table.durChapterPos,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get inShelf =>
      $composableBuilder(column: $table.inShelf, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceData => $composableBuilder(
    column: $table.sourceData,
    builder: (column) => column,
  );
}

class $$BooksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BooksTable,
          ShelfBook,
          $$BooksTableFilterComposer,
          $$BooksTableOrderingComposer,
          $$BooksTableAnnotationComposer,
          $$BooksTableCreateCompanionBuilder,
          $$BooksTableUpdateCompanionBuilder,
          (ShelfBook, BaseReferences<_$AppDatabase, $BooksTable, ShelfBook>),
          ShelfBook,
          PrefetchHooks Function()
        > {
  $$BooksTableTableManager(_$AppDatabase db, $BooksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BooksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BooksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BooksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> bookUrl = const Value.absent(),
                Value<String> origin = const Value.absent(),
                Value<String> originName = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> author = const Value.absent(),
                Value<String?> kind = const Value.absent(),
                Value<String?> coverUrl = const Value.absent(),
                Value<String?> intro = const Value.absent(),
                Value<String?> wordCount = const Value.absent(),
                Value<String?> latestChapterTitle = const Value.absent(),
                Value<int> durChapterIndex = const Value.absent(),
                Value<String?> durChapterUrl = const Value.absent(),
                Value<String?> durChapterTitle = const Value.absent(),
                Value<int> durChapterPos = const Value.absent(),
                Value<bool> inShelf = const Value.absent(),
                Value<DateTime?> addedAt = const Value.absent(),
                Value<DateTime?> lastReadAt = const Value.absent(),
                Value<String> sourceData = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BooksCompanion(
                bookUrl: bookUrl,
                origin: origin,
                originName: originName,
                name: name,
                author: author,
                kind: kind,
                coverUrl: coverUrl,
                intro: intro,
                wordCount: wordCount,
                latestChapterTitle: latestChapterTitle,
                durChapterIndex: durChapterIndex,
                durChapterUrl: durChapterUrl,
                durChapterTitle: durChapterTitle,
                durChapterPos: durChapterPos,
                inShelf: inShelf,
                addedAt: addedAt,
                lastReadAt: lastReadAt,
                sourceData: sourceData,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bookUrl,
                required String origin,
                required String originName,
                required String name,
                required String author,
                Value<String?> kind = const Value.absent(),
                Value<String?> coverUrl = const Value.absent(),
                Value<String?> intro = const Value.absent(),
                Value<String?> wordCount = const Value.absent(),
                Value<String?> latestChapterTitle = const Value.absent(),
                Value<int> durChapterIndex = const Value.absent(),
                Value<String?> durChapterUrl = const Value.absent(),
                Value<String?> durChapterTitle = const Value.absent(),
                Value<int> durChapterPos = const Value.absent(),
                Value<bool> inShelf = const Value.absent(),
                Value<DateTime?> addedAt = const Value.absent(),
                Value<DateTime?> lastReadAt = const Value.absent(),
                required String sourceData,
                Value<int> rowid = const Value.absent(),
              }) => BooksCompanion.insert(
                bookUrl: bookUrl,
                origin: origin,
                originName: originName,
                name: name,
                author: author,
                kind: kind,
                coverUrl: coverUrl,
                intro: intro,
                wordCount: wordCount,
                latestChapterTitle: latestChapterTitle,
                durChapterIndex: durChapterIndex,
                durChapterUrl: durChapterUrl,
                durChapterTitle: durChapterTitle,
                durChapterPos: durChapterPos,
                inShelf: inShelf,
                addedAt: addedAt,
                lastReadAt: lastReadAt,
                sourceData: sourceData,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BooksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BooksTable,
      ShelfBook,
      $$BooksTableFilterComposer,
      $$BooksTableOrderingComposer,
      $$BooksTableAnnotationComposer,
      $$BooksTableCreateCompanionBuilder,
      $$BooksTableUpdateCompanionBuilder,
      (ShelfBook, BaseReferences<_$AppDatabase, $BooksTable, ShelfBook>),
      ShelfBook,
      PrefetchHooks Function()
    >;
typedef $$ChaptersTableCreateCompanionBuilder =
    ChaptersCompanion Function({
      required String bookUrl,
      required int idx,
      required String url,
      required String title,
      required bool isVolume,
      required bool isVip,
      required bool isPay,
      Value<String?> tag,
      required String sourceData,
      Value<int> rowid,
    });
typedef $$ChaptersTableUpdateCompanionBuilder =
    ChaptersCompanion Function({
      Value<String> bookUrl,
      Value<int> idx,
      Value<String> url,
      Value<String> title,
      Value<bool> isVolume,
      Value<bool> isVip,
      Value<bool> isPay,
      Value<String?> tag,
      Value<String> sourceData,
      Value<int> rowid,
    });

class $$ChaptersTableFilterComposer
    extends Composer<_$AppDatabase, $ChaptersTable> {
  $$ChaptersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get bookUrl => $composableBuilder(
    column: $table.bookUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get idx => $composableBuilder(
    column: $table.idx,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isVolume => $composableBuilder(
    column: $table.isVolume,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isVip => $composableBuilder(
    column: $table.isVip,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPay => $composableBuilder(
    column: $table.isPay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tag => $composableBuilder(
    column: $table.tag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceData => $composableBuilder(
    column: $table.sourceData,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChaptersTableOrderingComposer
    extends Composer<_$AppDatabase, $ChaptersTable> {
  $$ChaptersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get bookUrl => $composableBuilder(
    column: $table.bookUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get idx => $composableBuilder(
    column: $table.idx,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isVolume => $composableBuilder(
    column: $table.isVolume,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isVip => $composableBuilder(
    column: $table.isVip,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPay => $composableBuilder(
    column: $table.isPay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tag => $composableBuilder(
    column: $table.tag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceData => $composableBuilder(
    column: $table.sourceData,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChaptersTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChaptersTable> {
  $$ChaptersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get bookUrl =>
      $composableBuilder(column: $table.bookUrl, builder: (column) => column);

  GeneratedColumn<int> get idx =>
      $composableBuilder(column: $table.idx, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<bool> get isVolume =>
      $composableBuilder(column: $table.isVolume, builder: (column) => column);

  GeneratedColumn<bool> get isVip =>
      $composableBuilder(column: $table.isVip, builder: (column) => column);

  GeneratedColumn<bool> get isPay =>
      $composableBuilder(column: $table.isPay, builder: (column) => column);

  GeneratedColumn<String> get tag =>
      $composableBuilder(column: $table.tag, builder: (column) => column);

  GeneratedColumn<String> get sourceData => $composableBuilder(
    column: $table.sourceData,
    builder: (column) => column,
  );
}

class $$ChaptersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChaptersTable,
          TocChapter,
          $$ChaptersTableFilterComposer,
          $$ChaptersTableOrderingComposer,
          $$ChaptersTableAnnotationComposer,
          $$ChaptersTableCreateCompanionBuilder,
          $$ChaptersTableUpdateCompanionBuilder,
          (
            TocChapter,
            BaseReferences<_$AppDatabase, $ChaptersTable, TocChapter>,
          ),
          TocChapter,
          PrefetchHooks Function()
        > {
  $$ChaptersTableTableManager(_$AppDatabase db, $ChaptersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChaptersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChaptersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChaptersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> bookUrl = const Value.absent(),
                Value<int> idx = const Value.absent(),
                Value<String> url = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<bool> isVolume = const Value.absent(),
                Value<bool> isVip = const Value.absent(),
                Value<bool> isPay = const Value.absent(),
                Value<String?> tag = const Value.absent(),
                Value<String> sourceData = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChaptersCompanion(
                bookUrl: bookUrl,
                idx: idx,
                url: url,
                title: title,
                isVolume: isVolume,
                isVip: isVip,
                isPay: isPay,
                tag: tag,
                sourceData: sourceData,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bookUrl,
                required int idx,
                required String url,
                required String title,
                required bool isVolume,
                required bool isVip,
                required bool isPay,
                Value<String?> tag = const Value.absent(),
                required String sourceData,
                Value<int> rowid = const Value.absent(),
              }) => ChaptersCompanion.insert(
                bookUrl: bookUrl,
                idx: idx,
                url: url,
                title: title,
                isVolume: isVolume,
                isVip: isVip,
                isPay: isPay,
                tag: tag,
                sourceData: sourceData,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChaptersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChaptersTable,
      TocChapter,
      $$ChaptersTableFilterComposer,
      $$ChaptersTableOrderingComposer,
      $$ChaptersTableAnnotationComposer,
      $$ChaptersTableCreateCompanionBuilder,
      $$ChaptersTableUpdateCompanionBuilder,
      (TocChapter, BaseReferences<_$AppDatabase, $ChaptersTable, TocChapter>),
      TocChapter,
      PrefetchHooks Function()
    >;
typedef $$ContentsTableCreateCompanionBuilder =
    ContentsCompanion Function({
      required String bookUrl,
      required String chapterUrl,
      required String title,
      required String content,
      Value<int> rowid,
    });
typedef $$ContentsTableUpdateCompanionBuilder =
    ContentsCompanion Function({
      Value<String> bookUrl,
      Value<String> chapterUrl,
      Value<String> title,
      Value<String> content,
      Value<int> rowid,
    });

class $$ContentsTableFilterComposer
    extends Composer<_$AppDatabase, $ContentsTable> {
  $$ContentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get bookUrl => $composableBuilder(
    column: $table.bookUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chapterUrl => $composableBuilder(
    column: $table.chapterUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ContentsTableOrderingComposer
    extends Composer<_$AppDatabase, $ContentsTable> {
  $$ContentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get bookUrl => $composableBuilder(
    column: $table.bookUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chapterUrl => $composableBuilder(
    column: $table.chapterUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ContentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ContentsTable> {
  $$ContentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get bookUrl =>
      $composableBuilder(column: $table.bookUrl, builder: (column) => column);

  GeneratedColumn<String> get chapterUrl => $composableBuilder(
    column: $table.chapterUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);
}

class $$ContentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ContentsTable,
          ContentRow,
          $$ContentsTableFilterComposer,
          $$ContentsTableOrderingComposer,
          $$ContentsTableAnnotationComposer,
          $$ContentsTableCreateCompanionBuilder,
          $$ContentsTableUpdateCompanionBuilder,
          (
            ContentRow,
            BaseReferences<_$AppDatabase, $ContentsTable, ContentRow>,
          ),
          ContentRow,
          PrefetchHooks Function()
        > {
  $$ContentsTableTableManager(_$AppDatabase db, $ContentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ContentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ContentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ContentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> bookUrl = const Value.absent(),
                Value<String> chapterUrl = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ContentsCompanion(
                bookUrl: bookUrl,
                chapterUrl: chapterUrl,
                title: title,
                content: content,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bookUrl,
                required String chapterUrl,
                required String title,
                required String content,
                Value<int> rowid = const Value.absent(),
              }) => ContentsCompanion.insert(
                bookUrl: bookUrl,
                chapterUrl: chapterUrl,
                title: title,
                content: content,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ContentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ContentsTable,
      ContentRow,
      $$ContentsTableFilterComposer,
      $$ContentsTableOrderingComposer,
      $$ContentsTableAnnotationComposer,
      $$ContentsTableCreateCompanionBuilder,
      $$ContentsTableUpdateCompanionBuilder,
      (ContentRow, BaseReferences<_$AppDatabase, $ContentsTable, ContentRow>),
      ContentRow,
      PrefetchHooks Function()
    >;
typedef $$SourceKvTableCreateCompanionBuilder =
    SourceKvCompanion Function({
      required String key,
      required String value,
      Value<DateTime?> deadline,
      Value<int> rowid,
    });
typedef $$SourceKvTableUpdateCompanionBuilder =
    SourceKvCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<DateTime?> deadline,
      Value<int> rowid,
    });

class $$SourceKvTableFilterComposer
    extends Composer<_$AppDatabase, $SourceKvTable> {
  $$SourceKvTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deadline => $composableBuilder(
    column: $table.deadline,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SourceKvTableOrderingComposer
    extends Composer<_$AppDatabase, $SourceKvTable> {
  $$SourceKvTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deadline => $composableBuilder(
    column: $table.deadline,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SourceKvTableAnnotationComposer
    extends Composer<_$AppDatabase, $SourceKvTable> {
  $$SourceKvTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<DateTime> get deadline =>
      $composableBuilder(column: $table.deadline, builder: (column) => column);
}

class $$SourceKvTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SourceKvTable,
          SourceKvRow,
          $$SourceKvTableFilterComposer,
          $$SourceKvTableOrderingComposer,
          $$SourceKvTableAnnotationComposer,
          $$SourceKvTableCreateCompanionBuilder,
          $$SourceKvTableUpdateCompanionBuilder,
          (
            SourceKvRow,
            BaseReferences<_$AppDatabase, $SourceKvTable, SourceKvRow>,
          ),
          SourceKvRow,
          PrefetchHooks Function()
        > {
  $$SourceKvTableTableManager(_$AppDatabase db, $SourceKvTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SourceKvTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SourceKvTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SourceKvTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<DateTime?> deadline = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SourceKvCompanion(
                key: key,
                value: value,
                deadline: deadline,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<DateTime?> deadline = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SourceKvCompanion.insert(
                key: key,
                value: value,
                deadline: deadline,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SourceKvTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SourceKvTable,
      SourceKvRow,
      $$SourceKvTableFilterComposer,
      $$SourceKvTableOrderingComposer,
      $$SourceKvTableAnnotationComposer,
      $$SourceKvTableCreateCompanionBuilder,
      $$SourceKvTableUpdateCompanionBuilder,
      (SourceKvRow, BaseReferences<_$AppDatabase, $SourceKvTable, SourceKvRow>),
      SourceKvRow,
      PrefetchHooks Function()
    >;
typedef $$CookiesTableCreateCompanionBuilder =
    CookiesCompanion Function({
      required String domain,
      required String cookie,
      Value<int> rowid,
    });
typedef $$CookiesTableUpdateCompanionBuilder =
    CookiesCompanion Function({
      Value<String> domain,
      Value<String> cookie,
      Value<int> rowid,
    });

class $$CookiesTableFilterComposer
    extends Composer<_$AppDatabase, $CookiesTable> {
  $$CookiesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get domain => $composableBuilder(
    column: $table.domain,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cookie => $composableBuilder(
    column: $table.cookie,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CookiesTableOrderingComposer
    extends Composer<_$AppDatabase, $CookiesTable> {
  $$CookiesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get domain => $composableBuilder(
    column: $table.domain,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cookie => $composableBuilder(
    column: $table.cookie,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CookiesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CookiesTable> {
  $$CookiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get domain =>
      $composableBuilder(column: $table.domain, builder: (column) => column);

  GeneratedColumn<String> get cookie =>
      $composableBuilder(column: $table.cookie, builder: (column) => column);
}

class $$CookiesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CookiesTable,
          CookieRow,
          $$CookiesTableFilterComposer,
          $$CookiesTableOrderingComposer,
          $$CookiesTableAnnotationComposer,
          $$CookiesTableCreateCompanionBuilder,
          $$CookiesTableUpdateCompanionBuilder,
          (CookieRow, BaseReferences<_$AppDatabase, $CookiesTable, CookieRow>),
          CookieRow,
          PrefetchHooks Function()
        > {
  $$CookiesTableTableManager(_$AppDatabase db, $CookiesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CookiesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CookiesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CookiesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> domain = const Value.absent(),
                Value<String> cookie = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CookiesCompanion(
                domain: domain,
                cookie: cookie,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String domain,
                required String cookie,
                Value<int> rowid = const Value.absent(),
              }) => CookiesCompanion.insert(
                domain: domain,
                cookie: cookie,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CookiesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CookiesTable,
      CookieRow,
      $$CookiesTableFilterComposer,
      $$CookiesTableOrderingComposer,
      $$CookiesTableAnnotationComposer,
      $$CookiesTableCreateCompanionBuilder,
      $$CookiesTableUpdateCompanionBuilder,
      (CookieRow, BaseReferences<_$AppDatabase, $CookiesTable, CookieRow>),
      CookieRow,
      PrefetchHooks Function()
    >;
typedef $$SettingsTableCreateCompanionBuilder =
    SettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$SettingsTableUpdateCompanionBuilder =
    SettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$SettingsTableFilterComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SettingsTable,
          SettingRow,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (
            SettingRow,
            BaseReferences<_$AppDatabase, $SettingsTable, SettingRow>,
          ),
          SettingRow,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$AppDatabase db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SettingsTable,
      SettingRow,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (SettingRow, BaseReferences<_$AppDatabase, $SettingsTable, SettingRow>),
      SettingRow,
      PrefetchHooks Function()
    >;
typedef $$SearchKeywordsTableCreateCompanionBuilder =
    SearchKeywordsCompanion Function({
      required String word,
      required int usage,
      required DateTime lastUsed,
      Value<int> rowid,
    });
typedef $$SearchKeywordsTableUpdateCompanionBuilder =
    SearchKeywordsCompanion Function({
      Value<String> word,
      Value<int> usage,
      Value<DateTime> lastUsed,
      Value<int> rowid,
    });

class $$SearchKeywordsTableFilterComposer
    extends Composer<_$AppDatabase, $SearchKeywordsTable> {
  $$SearchKeywordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get word => $composableBuilder(
    column: $table.word,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get usage => $composableBuilder(
    column: $table.usage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastUsed => $composableBuilder(
    column: $table.lastUsed,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SearchKeywordsTableOrderingComposer
    extends Composer<_$AppDatabase, $SearchKeywordsTable> {
  $$SearchKeywordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get word => $composableBuilder(
    column: $table.word,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get usage => $composableBuilder(
    column: $table.usage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastUsed => $composableBuilder(
    column: $table.lastUsed,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SearchKeywordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SearchKeywordsTable> {
  $$SearchKeywordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get word =>
      $composableBuilder(column: $table.word, builder: (column) => column);

  GeneratedColumn<int> get usage =>
      $composableBuilder(column: $table.usage, builder: (column) => column);

  GeneratedColumn<DateTime> get lastUsed =>
      $composableBuilder(column: $table.lastUsed, builder: (column) => column);
}

class $$SearchKeywordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SearchKeywordsTable,
          SearchKeywordRow,
          $$SearchKeywordsTableFilterComposer,
          $$SearchKeywordsTableOrderingComposer,
          $$SearchKeywordsTableAnnotationComposer,
          $$SearchKeywordsTableCreateCompanionBuilder,
          $$SearchKeywordsTableUpdateCompanionBuilder,
          (
            SearchKeywordRow,
            BaseReferences<
              _$AppDatabase,
              $SearchKeywordsTable,
              SearchKeywordRow
            >,
          ),
          SearchKeywordRow,
          PrefetchHooks Function()
        > {
  $$SearchKeywordsTableTableManager(
    _$AppDatabase db,
    $SearchKeywordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SearchKeywordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SearchKeywordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SearchKeywordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> word = const Value.absent(),
                Value<int> usage = const Value.absent(),
                Value<DateTime> lastUsed = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SearchKeywordsCompanion(
                word: word,
                usage: usage,
                lastUsed: lastUsed,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String word,
                required int usage,
                required DateTime lastUsed,
                Value<int> rowid = const Value.absent(),
              }) => SearchKeywordsCompanion.insert(
                word: word,
                usage: usage,
                lastUsed: lastUsed,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SearchKeywordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SearchKeywordsTable,
      SearchKeywordRow,
      $$SearchKeywordsTableFilterComposer,
      $$SearchKeywordsTableOrderingComposer,
      $$SearchKeywordsTableAnnotationComposer,
      $$SearchKeywordsTableCreateCompanionBuilder,
      $$SearchKeywordsTableUpdateCompanionBuilder,
      (
        SearchKeywordRow,
        BaseReferences<_$AppDatabase, $SearchKeywordsTable, SearchKeywordRow>,
      ),
      SearchKeywordRow,
      PrefetchHooks Function()
    >;
typedef $$CachedImagesTableCreateCompanionBuilder =
    CachedImagesCompanion Function({
      required String bookUrl,
      required String src,
      required Uint8List bytes,
      Value<int> rowid,
    });
typedef $$CachedImagesTableUpdateCompanionBuilder =
    CachedImagesCompanion Function({
      Value<String> bookUrl,
      Value<String> src,
      Value<Uint8List> bytes,
      Value<int> rowid,
    });

class $$CachedImagesTableFilterComposer
    extends Composer<_$AppDatabase, $CachedImagesTable> {
  $$CachedImagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get bookUrl => $composableBuilder(
    column: $table.bookUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get src => $composableBuilder(
    column: $table.src,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedImagesTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedImagesTable> {
  $$CachedImagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get bookUrl => $composableBuilder(
    column: $table.bookUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get src => $composableBuilder(
    column: $table.src,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedImagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedImagesTable> {
  $$CachedImagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get bookUrl =>
      $composableBuilder(column: $table.bookUrl, builder: (column) => column);

  GeneratedColumn<String> get src =>
      $composableBuilder(column: $table.src, builder: (column) => column);

  GeneratedColumn<Uint8List> get bytes =>
      $composableBuilder(column: $table.bytes, builder: (column) => column);
}

class $$CachedImagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedImagesTable,
          ContentImageRow,
          $$CachedImagesTableFilterComposer,
          $$CachedImagesTableOrderingComposer,
          $$CachedImagesTableAnnotationComposer,
          $$CachedImagesTableCreateCompanionBuilder,
          $$CachedImagesTableUpdateCompanionBuilder,
          (
            ContentImageRow,
            BaseReferences<_$AppDatabase, $CachedImagesTable, ContentImageRow>,
          ),
          ContentImageRow,
          PrefetchHooks Function()
        > {
  $$CachedImagesTableTableManager(_$AppDatabase db, $CachedImagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedImagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedImagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedImagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> bookUrl = const Value.absent(),
                Value<String> src = const Value.absent(),
                Value<Uint8List> bytes = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedImagesCompanion(
                bookUrl: bookUrl,
                src: src,
                bytes: bytes,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bookUrl,
                required String src,
                required Uint8List bytes,
                Value<int> rowid = const Value.absent(),
              }) => CachedImagesCompanion.insert(
                bookUrl: bookUrl,
                src: src,
                bytes: bytes,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedImagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedImagesTable,
      ContentImageRow,
      $$CachedImagesTableFilterComposer,
      $$CachedImagesTableOrderingComposer,
      $$CachedImagesTableAnnotationComposer,
      $$CachedImagesTableCreateCompanionBuilder,
      $$CachedImagesTableUpdateCompanionBuilder,
      (
        ContentImageRow,
        BaseReferences<_$AppDatabase, $CachedImagesTable, ContentImageRow>,
      ),
      ContentImageRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$SourcesTableTableManager get sources =>
      $$SourcesTableTableManager(_db, _db.sources);
  $$ReplaceRulesTableTableManager get replaceRules =>
      $$ReplaceRulesTableTableManager(_db, _db.replaceRules);
  $$BooksTableTableManager get books =>
      $$BooksTableTableManager(_db, _db.books);
  $$ChaptersTableTableManager get chapters =>
      $$ChaptersTableTableManager(_db, _db.chapters);
  $$ContentsTableTableManager get contents =>
      $$ContentsTableTableManager(_db, _db.contents);
  $$SourceKvTableTableManager get sourceKv =>
      $$SourceKvTableTableManager(_db, _db.sourceKv);
  $$CookiesTableTableManager get cookies =>
      $$CookiesTableTableManager(_db, _db.cookies);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
  $$SearchKeywordsTableTableManager get searchKeywords =>
      $$SearchKeywordsTableTableManager(_db, _db.searchKeywords);
  $$CachedImagesTableTableManager get cachedImages =>
      $$CachedImagesTableTableManager(_db, _db.cachedImages);
}
