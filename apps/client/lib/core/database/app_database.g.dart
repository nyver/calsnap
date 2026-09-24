// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $MealsTable extends Meals with TableInfo<$MealsTable, MealRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MealsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mealTimeMeta = const VerificationMeta(
    'mealTime',
  );
  @override
  late final GeneratedColumn<int> mealTime = GeneratedColumn<int>(
    'meal_time',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mealTypeMeta = const VerificationMeta(
    'mealType',
  );
  @override
  late final GeneratedColumn<String> mealType = GeneratedColumn<String>(
    'meal_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _photoPathMeta = const VerificationMeta(
    'photoPath',
  );
  @override
  late final GeneratedColumn<String> photoPath = GeneratedColumn<String>(
    'photo_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _totalKcalMeta = const VerificationMeta(
    'totalKcal',
  );
  @override
  late final GeneratedColumn<double> totalKcal = GeneratedColumn<double>(
    'total_kcal',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _totalProteinMeta = const VerificationMeta(
    'totalProtein',
  );
  @override
  late final GeneratedColumn<double> totalProtein = GeneratedColumn<double>(
    'total_protein',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _totalFatMeta = const VerificationMeta(
    'totalFat',
  );
  @override
  late final GeneratedColumn<double> totalFat = GeneratedColumn<double>(
    'total_fat',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _totalCarbsMeta = const VerificationMeta(
    'totalCarbs',
  );
  @override
  late final GeneratedColumn<double> totalCarbs = GeneratedColumn<double>(
    'total_carbs',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _aiProviderMeta = const VerificationMeta(
    'aiProvider',
  );
  @override
  late final GeneratedColumn<String> aiProvider = GeneratedColumn<String>(
    'ai_provider',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _aiModelMeta = const VerificationMeta(
    'aiModel',
  );
  @override
  late final GeneratedColumn<String> aiModel = GeneratedColumn<String>(
    'ai_model',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    mealTime,
    mealType,
    photoPath,
    totalKcal,
    totalProtein,
    totalFat,
    totalCarbs,
    aiProvider,
    aiModel,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'meals';
  @override
  VerificationContext validateIntegrity(
    Insertable<MealRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('meal_time')) {
      context.handle(
        _mealTimeMeta,
        mealTime.isAcceptableOrUnknown(data['meal_time']!, _mealTimeMeta),
      );
    } else if (isInserting) {
      context.missing(_mealTimeMeta);
    }
    if (data.containsKey('meal_type')) {
      context.handle(
        _mealTypeMeta,
        mealType.isAcceptableOrUnknown(data['meal_type']!, _mealTypeMeta),
      );
    }
    if (data.containsKey('photo_path')) {
      context.handle(
        _photoPathMeta,
        photoPath.isAcceptableOrUnknown(data['photo_path']!, _photoPathMeta),
      );
    }
    if (data.containsKey('total_kcal')) {
      context.handle(
        _totalKcalMeta,
        totalKcal.isAcceptableOrUnknown(data['total_kcal']!, _totalKcalMeta),
      );
    }
    if (data.containsKey('total_protein')) {
      context.handle(
        _totalProteinMeta,
        totalProtein.isAcceptableOrUnknown(
          data['total_protein']!,
          _totalProteinMeta,
        ),
      );
    }
    if (data.containsKey('total_fat')) {
      context.handle(
        _totalFatMeta,
        totalFat.isAcceptableOrUnknown(data['total_fat']!, _totalFatMeta),
      );
    }
    if (data.containsKey('total_carbs')) {
      context.handle(
        _totalCarbsMeta,
        totalCarbs.isAcceptableOrUnknown(data['total_carbs']!, _totalCarbsMeta),
      );
    }
    if (data.containsKey('ai_provider')) {
      context.handle(
        _aiProviderMeta,
        aiProvider.isAcceptableOrUnknown(data['ai_provider']!, _aiProviderMeta),
      );
    }
    if (data.containsKey('ai_model')) {
      context.handle(
        _aiModelMeta,
        aiModel.isAcceptableOrUnknown(data['ai_model']!, _aiModelMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MealRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MealRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      mealTime: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}meal_time'],
      )!,
      mealType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}meal_type'],
      ),
      photoPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}photo_path'],
      ),
      totalKcal: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}total_kcal'],
      )!,
      totalProtein: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}total_protein'],
      )!,
      totalFat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}total_fat'],
      )!,
      totalCarbs: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}total_carbs'],
      )!,
      aiProvider: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ai_provider'],
      ),
      aiModel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ai_model'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $MealsTable createAlias(String alias) {
    return $MealsTable(attachedDatabase, alias);
  }
}

class MealRow extends DataClass implements Insertable<MealRow> {
  final String id;

  /// UTC epoch milliseconds.
  final int mealTime;
  final String? mealType;

  /// Path relative to the app documents directory.
  final String? photoPath;
  final double totalKcal;
  final double totalProtein;
  final double totalFat;
  final double totalCarbs;
  final String? aiProvider;
  final String? aiModel;
  final int createdAt;
  final int updatedAt;
  const MealRow({
    required this.id,
    required this.mealTime,
    this.mealType,
    this.photoPath,
    required this.totalKcal,
    required this.totalProtein,
    required this.totalFat,
    required this.totalCarbs,
    this.aiProvider,
    this.aiModel,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['meal_time'] = Variable<int>(mealTime);
    if (!nullToAbsent || mealType != null) {
      map['meal_type'] = Variable<String>(mealType);
    }
    if (!nullToAbsent || photoPath != null) {
      map['photo_path'] = Variable<String>(photoPath);
    }
    map['total_kcal'] = Variable<double>(totalKcal);
    map['total_protein'] = Variable<double>(totalProtein);
    map['total_fat'] = Variable<double>(totalFat);
    map['total_carbs'] = Variable<double>(totalCarbs);
    if (!nullToAbsent || aiProvider != null) {
      map['ai_provider'] = Variable<String>(aiProvider);
    }
    if (!nullToAbsent || aiModel != null) {
      map['ai_model'] = Variable<String>(aiModel);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  MealsCompanion toCompanion(bool nullToAbsent) {
    return MealsCompanion(
      id: Value(id),
      mealTime: Value(mealTime),
      mealType: mealType == null && nullToAbsent
          ? const Value.absent()
          : Value(mealType),
      photoPath: photoPath == null && nullToAbsent
          ? const Value.absent()
          : Value(photoPath),
      totalKcal: Value(totalKcal),
      totalProtein: Value(totalProtein),
      totalFat: Value(totalFat),
      totalCarbs: Value(totalCarbs),
      aiProvider: aiProvider == null && nullToAbsent
          ? const Value.absent()
          : Value(aiProvider),
      aiModel: aiModel == null && nullToAbsent
          ? const Value.absent()
          : Value(aiModel),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory MealRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MealRow(
      id: serializer.fromJson<String>(json['id']),
      mealTime: serializer.fromJson<int>(json['mealTime']),
      mealType: serializer.fromJson<String?>(json['mealType']),
      photoPath: serializer.fromJson<String?>(json['photoPath']),
      totalKcal: serializer.fromJson<double>(json['totalKcal']),
      totalProtein: serializer.fromJson<double>(json['totalProtein']),
      totalFat: serializer.fromJson<double>(json['totalFat']),
      totalCarbs: serializer.fromJson<double>(json['totalCarbs']),
      aiProvider: serializer.fromJson<String?>(json['aiProvider']),
      aiModel: serializer.fromJson<String?>(json['aiModel']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'mealTime': serializer.toJson<int>(mealTime),
      'mealType': serializer.toJson<String?>(mealType),
      'photoPath': serializer.toJson<String?>(photoPath),
      'totalKcal': serializer.toJson<double>(totalKcal),
      'totalProtein': serializer.toJson<double>(totalProtein),
      'totalFat': serializer.toJson<double>(totalFat),
      'totalCarbs': serializer.toJson<double>(totalCarbs),
      'aiProvider': serializer.toJson<String?>(aiProvider),
      'aiModel': serializer.toJson<String?>(aiModel),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  MealRow copyWith({
    String? id,
    int? mealTime,
    Value<String?> mealType = const Value.absent(),
    Value<String?> photoPath = const Value.absent(),
    double? totalKcal,
    double? totalProtein,
    double? totalFat,
    double? totalCarbs,
    Value<String?> aiProvider = const Value.absent(),
    Value<String?> aiModel = const Value.absent(),
    int? createdAt,
    int? updatedAt,
  }) => MealRow(
    id: id ?? this.id,
    mealTime: mealTime ?? this.mealTime,
    mealType: mealType.present ? mealType.value : this.mealType,
    photoPath: photoPath.present ? photoPath.value : this.photoPath,
    totalKcal: totalKcal ?? this.totalKcal,
    totalProtein: totalProtein ?? this.totalProtein,
    totalFat: totalFat ?? this.totalFat,
    totalCarbs: totalCarbs ?? this.totalCarbs,
    aiProvider: aiProvider.present ? aiProvider.value : this.aiProvider,
    aiModel: aiModel.present ? aiModel.value : this.aiModel,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  MealRow copyWithCompanion(MealsCompanion data) {
    return MealRow(
      id: data.id.present ? data.id.value : this.id,
      mealTime: data.mealTime.present ? data.mealTime.value : this.mealTime,
      mealType: data.mealType.present ? data.mealType.value : this.mealType,
      photoPath: data.photoPath.present ? data.photoPath.value : this.photoPath,
      totalKcal: data.totalKcal.present ? data.totalKcal.value : this.totalKcal,
      totalProtein: data.totalProtein.present
          ? data.totalProtein.value
          : this.totalProtein,
      totalFat: data.totalFat.present ? data.totalFat.value : this.totalFat,
      totalCarbs: data.totalCarbs.present
          ? data.totalCarbs.value
          : this.totalCarbs,
      aiProvider: data.aiProvider.present
          ? data.aiProvider.value
          : this.aiProvider,
      aiModel: data.aiModel.present ? data.aiModel.value : this.aiModel,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MealRow(')
          ..write('id: $id, ')
          ..write('mealTime: $mealTime, ')
          ..write('mealType: $mealType, ')
          ..write('photoPath: $photoPath, ')
          ..write('totalKcal: $totalKcal, ')
          ..write('totalProtein: $totalProtein, ')
          ..write('totalFat: $totalFat, ')
          ..write('totalCarbs: $totalCarbs, ')
          ..write('aiProvider: $aiProvider, ')
          ..write('aiModel: $aiModel, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    mealTime,
    mealType,
    photoPath,
    totalKcal,
    totalProtein,
    totalFat,
    totalCarbs,
    aiProvider,
    aiModel,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MealRow &&
          other.id == this.id &&
          other.mealTime == this.mealTime &&
          other.mealType == this.mealType &&
          other.photoPath == this.photoPath &&
          other.totalKcal == this.totalKcal &&
          other.totalProtein == this.totalProtein &&
          other.totalFat == this.totalFat &&
          other.totalCarbs == this.totalCarbs &&
          other.aiProvider == this.aiProvider &&
          other.aiModel == this.aiModel &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class MealsCompanion extends UpdateCompanion<MealRow> {
  final Value<String> id;
  final Value<int> mealTime;
  final Value<String?> mealType;
  final Value<String?> photoPath;
  final Value<double> totalKcal;
  final Value<double> totalProtein;
  final Value<double> totalFat;
  final Value<double> totalCarbs;
  final Value<String?> aiProvider;
  final Value<String?> aiModel;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const MealsCompanion({
    this.id = const Value.absent(),
    this.mealTime = const Value.absent(),
    this.mealType = const Value.absent(),
    this.photoPath = const Value.absent(),
    this.totalKcal = const Value.absent(),
    this.totalProtein = const Value.absent(),
    this.totalFat = const Value.absent(),
    this.totalCarbs = const Value.absent(),
    this.aiProvider = const Value.absent(),
    this.aiModel = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MealsCompanion.insert({
    required String id,
    required int mealTime,
    this.mealType = const Value.absent(),
    this.photoPath = const Value.absent(),
    this.totalKcal = const Value.absent(),
    this.totalProtein = const Value.absent(),
    this.totalFat = const Value.absent(),
    this.totalCarbs = const Value.absent(),
    this.aiProvider = const Value.absent(),
    this.aiModel = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       mealTime = Value(mealTime),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<MealRow> custom({
    Expression<String>? id,
    Expression<int>? mealTime,
    Expression<String>? mealType,
    Expression<String>? photoPath,
    Expression<double>? totalKcal,
    Expression<double>? totalProtein,
    Expression<double>? totalFat,
    Expression<double>? totalCarbs,
    Expression<String>? aiProvider,
    Expression<String>? aiModel,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (mealTime != null) 'meal_time': mealTime,
      if (mealType != null) 'meal_type': mealType,
      if (photoPath != null) 'photo_path': photoPath,
      if (totalKcal != null) 'total_kcal': totalKcal,
      if (totalProtein != null) 'total_protein': totalProtein,
      if (totalFat != null) 'total_fat': totalFat,
      if (totalCarbs != null) 'total_carbs': totalCarbs,
      if (aiProvider != null) 'ai_provider': aiProvider,
      if (aiModel != null) 'ai_model': aiModel,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MealsCompanion copyWith({
    Value<String>? id,
    Value<int>? mealTime,
    Value<String?>? mealType,
    Value<String?>? photoPath,
    Value<double>? totalKcal,
    Value<double>? totalProtein,
    Value<double>? totalFat,
    Value<double>? totalCarbs,
    Value<String?>? aiProvider,
    Value<String?>? aiModel,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return MealsCompanion(
      id: id ?? this.id,
      mealTime: mealTime ?? this.mealTime,
      mealType: mealType ?? this.mealType,
      photoPath: photoPath ?? this.photoPath,
      totalKcal: totalKcal ?? this.totalKcal,
      totalProtein: totalProtein ?? this.totalProtein,
      totalFat: totalFat ?? this.totalFat,
      totalCarbs: totalCarbs ?? this.totalCarbs,
      aiProvider: aiProvider ?? this.aiProvider,
      aiModel: aiModel ?? this.aiModel,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (mealTime.present) {
      map['meal_time'] = Variable<int>(mealTime.value);
    }
    if (mealType.present) {
      map['meal_type'] = Variable<String>(mealType.value);
    }
    if (photoPath.present) {
      map['photo_path'] = Variable<String>(photoPath.value);
    }
    if (totalKcal.present) {
      map['total_kcal'] = Variable<double>(totalKcal.value);
    }
    if (totalProtein.present) {
      map['total_protein'] = Variable<double>(totalProtein.value);
    }
    if (totalFat.present) {
      map['total_fat'] = Variable<double>(totalFat.value);
    }
    if (totalCarbs.present) {
      map['total_carbs'] = Variable<double>(totalCarbs.value);
    }
    if (aiProvider.present) {
      map['ai_provider'] = Variable<String>(aiProvider.value);
    }
    if (aiModel.present) {
      map['ai_model'] = Variable<String>(aiModel.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MealsCompanion(')
          ..write('id: $id, ')
          ..write('mealTime: $mealTime, ')
          ..write('mealType: $mealType, ')
          ..write('photoPath: $photoPath, ')
          ..write('totalKcal: $totalKcal, ')
          ..write('totalProtein: $totalProtein, ')
          ..write('totalFat: $totalFat, ')
          ..write('totalCarbs: $totalCarbs, ')
          ..write('aiProvider: $aiProvider, ')
          ..write('aiModel: $aiModel, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MealItemsTable extends MealItems
    with TableInfo<$MealItemsTable, MealItemRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MealItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mealIdMeta = const VerificationMeta('mealId');
  @override
  late final GeneratedColumn<String> mealId = GeneratedColumn<String>(
    'meal_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES meals (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _foodIdMeta = const VerificationMeta('foodId');
  @override
  late final GeneratedColumn<String> foodId = GeneratedColumn<String>(
    'food_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
  static const VerificationMeta _estimatedWeightGMeta = const VerificationMeta(
    'estimatedWeightG',
  );
  @override
  late final GeneratedColumn<double> estimatedWeightG = GeneratedColumn<double>(
    'estimated_weight_g',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _weightGMeta = const VerificationMeta(
    'weightG',
  );
  @override
  late final GeneratedColumn<double> weightG = GeneratedColumn<double>(
    'weight_g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kcalPer100gMeta = const VerificationMeta(
    'kcalPer100g',
  );
  @override
  late final GeneratedColumn<double> kcalPer100g = GeneratedColumn<double>(
    'kcal_per_100g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _proteinPer100gMeta = const VerificationMeta(
    'proteinPer100g',
  );
  @override
  late final GeneratedColumn<double> proteinPer100g = GeneratedColumn<double>(
    'protein_per_100g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _fatPer100gMeta = const VerificationMeta(
    'fatPer100g',
  );
  @override
  late final GeneratedColumn<double> fatPer100g = GeneratedColumn<double>(
    'fat_per_100g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _carbsPer100gMeta = const VerificationMeta(
    'carbsPer100g',
  );
  @override
  late final GeneratedColumn<double> carbsPer100g = GeneratedColumn<double>(
    'carbs_per_100g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _kcalMeta = const VerificationMeta('kcal');
  @override
  late final GeneratedColumn<double> kcal = GeneratedColumn<double>(
    'kcal',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _proteinMeta = const VerificationMeta(
    'protein',
  );
  @override
  late final GeneratedColumn<double> protein = GeneratedColumn<double>(
    'protein',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _fatMeta = const VerificationMeta('fat');
  @override
  late final GeneratedColumn<double> fat = GeneratedColumn<double>(
    'fat',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _carbsMeta = const VerificationMeta('carbs');
  @override
  late final GeneratedColumn<double> carbs = GeneratedColumn<double>(
    'carbs',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _confidenceMeta = const VerificationMeta(
    'confidence',
  );
  @override
  late final GeneratedColumn<double> confidence = GeneratedColumn<double>(
    'confidence',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _recognitionSourceMeta = const VerificationMeta(
    'recognitionSource',
  );
  @override
  late final GeneratedColumn<String> recognitionSource =
      GeneratedColumn<String>(
        'recognition_source',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _wasCorrectedMeta = const VerificationMeta(
    'wasCorrected',
  );
  @override
  late final GeneratedColumn<bool> wasCorrected = GeneratedColumn<bool>(
    'was_corrected',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("was_corrected" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    mealId,
    foodId,
    name,
    estimatedWeightG,
    weightG,
    kcalPer100g,
    proteinPer100g,
    fatPer100g,
    carbsPer100g,
    kcal,
    protein,
    fat,
    carbs,
    confidence,
    recognitionSource,
    wasCorrected,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'meal_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<MealItemRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('meal_id')) {
      context.handle(
        _mealIdMeta,
        mealId.isAcceptableOrUnknown(data['meal_id']!, _mealIdMeta),
      );
    } else if (isInserting) {
      context.missing(_mealIdMeta);
    }
    if (data.containsKey('food_id')) {
      context.handle(
        _foodIdMeta,
        foodId.isAcceptableOrUnknown(data['food_id']!, _foodIdMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('estimated_weight_g')) {
      context.handle(
        _estimatedWeightGMeta,
        estimatedWeightG.isAcceptableOrUnknown(
          data['estimated_weight_g']!,
          _estimatedWeightGMeta,
        ),
      );
    }
    if (data.containsKey('weight_g')) {
      context.handle(
        _weightGMeta,
        weightG.isAcceptableOrUnknown(data['weight_g']!, _weightGMeta),
      );
    } else if (isInserting) {
      context.missing(_weightGMeta);
    }
    if (data.containsKey('kcal_per_100g')) {
      context.handle(
        _kcalPer100gMeta,
        kcalPer100g.isAcceptableOrUnknown(
          data['kcal_per_100g']!,
          _kcalPer100gMeta,
        ),
      );
    }
    if (data.containsKey('protein_per_100g')) {
      context.handle(
        _proteinPer100gMeta,
        proteinPer100g.isAcceptableOrUnknown(
          data['protein_per_100g']!,
          _proteinPer100gMeta,
        ),
      );
    }
    if (data.containsKey('fat_per_100g')) {
      context.handle(
        _fatPer100gMeta,
        fatPer100g.isAcceptableOrUnknown(
          data['fat_per_100g']!,
          _fatPer100gMeta,
        ),
      );
    }
    if (data.containsKey('carbs_per_100g')) {
      context.handle(
        _carbsPer100gMeta,
        carbsPer100g.isAcceptableOrUnknown(
          data['carbs_per_100g']!,
          _carbsPer100gMeta,
        ),
      );
    }
    if (data.containsKey('kcal')) {
      context.handle(
        _kcalMeta,
        kcal.isAcceptableOrUnknown(data['kcal']!, _kcalMeta),
      );
    }
    if (data.containsKey('protein')) {
      context.handle(
        _proteinMeta,
        protein.isAcceptableOrUnknown(data['protein']!, _proteinMeta),
      );
    }
    if (data.containsKey('fat')) {
      context.handle(
        _fatMeta,
        fat.isAcceptableOrUnknown(data['fat']!, _fatMeta),
      );
    }
    if (data.containsKey('carbs')) {
      context.handle(
        _carbsMeta,
        carbs.isAcceptableOrUnknown(data['carbs']!, _carbsMeta),
      );
    }
    if (data.containsKey('confidence')) {
      context.handle(
        _confidenceMeta,
        confidence.isAcceptableOrUnknown(data['confidence']!, _confidenceMeta),
      );
    }
    if (data.containsKey('recognition_source')) {
      context.handle(
        _recognitionSourceMeta,
        recognitionSource.isAcceptableOrUnknown(
          data['recognition_source']!,
          _recognitionSourceMeta,
        ),
      );
    }
    if (data.containsKey('was_corrected')) {
      context.handle(
        _wasCorrectedMeta,
        wasCorrected.isAcceptableOrUnknown(
          data['was_corrected']!,
          _wasCorrectedMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MealItemRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MealItemRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      mealId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}meal_id'],
      )!,
      foodId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}food_id'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      estimatedWeightG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}estimated_weight_g'],
      ),
      weightG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}weight_g'],
      )!,
      kcalPer100g: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}kcal_per_100g'],
      )!,
      proteinPer100g: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}protein_per_100g'],
      )!,
      fatPer100g: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}fat_per_100g'],
      )!,
      carbsPer100g: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}carbs_per_100g'],
      )!,
      kcal: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}kcal'],
      )!,
      protein: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}protein'],
      )!,
      fat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}fat'],
      )!,
      carbs: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}carbs'],
      )!,
      confidence: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}confidence'],
      ),
      recognitionSource: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recognition_source'],
      ),
      wasCorrected: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}was_corrected'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $MealItemsTable createAlias(String alias) {
    return $MealItemsTable(attachedDatabase, alias);
  }
}

class MealItemRow extends DataClass implements Insertable<MealItemRow> {
  final String id;
  final String mealId;
  final String? foodId;
  final String name;
  final double? estimatedWeightG;
  final double weightG;
  final double kcalPer100g;
  final double proteinPer100g;
  final double fatPer100g;
  final double carbsPer100g;
  final double kcal;
  final double protein;
  final double fat;
  final double carbs;
  final double? confidence;
  final String? recognitionSource;
  final bool wasCorrected;
  final int createdAt;
  final int updatedAt;
  const MealItemRow({
    required this.id,
    required this.mealId,
    this.foodId,
    required this.name,
    this.estimatedWeightG,
    required this.weightG,
    required this.kcalPer100g,
    required this.proteinPer100g,
    required this.fatPer100g,
    required this.carbsPer100g,
    required this.kcal,
    required this.protein,
    required this.fat,
    required this.carbs,
    this.confidence,
    this.recognitionSource,
    required this.wasCorrected,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['meal_id'] = Variable<String>(mealId);
    if (!nullToAbsent || foodId != null) {
      map['food_id'] = Variable<String>(foodId);
    }
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || estimatedWeightG != null) {
      map['estimated_weight_g'] = Variable<double>(estimatedWeightG);
    }
    map['weight_g'] = Variable<double>(weightG);
    map['kcal_per_100g'] = Variable<double>(kcalPer100g);
    map['protein_per_100g'] = Variable<double>(proteinPer100g);
    map['fat_per_100g'] = Variable<double>(fatPer100g);
    map['carbs_per_100g'] = Variable<double>(carbsPer100g);
    map['kcal'] = Variable<double>(kcal);
    map['protein'] = Variable<double>(protein);
    map['fat'] = Variable<double>(fat);
    map['carbs'] = Variable<double>(carbs);
    if (!nullToAbsent || confidence != null) {
      map['confidence'] = Variable<double>(confidence);
    }
    if (!nullToAbsent || recognitionSource != null) {
      map['recognition_source'] = Variable<String>(recognitionSource);
    }
    map['was_corrected'] = Variable<bool>(wasCorrected);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  MealItemsCompanion toCompanion(bool nullToAbsent) {
    return MealItemsCompanion(
      id: Value(id),
      mealId: Value(mealId),
      foodId: foodId == null && nullToAbsent
          ? const Value.absent()
          : Value(foodId),
      name: Value(name),
      estimatedWeightG: estimatedWeightG == null && nullToAbsent
          ? const Value.absent()
          : Value(estimatedWeightG),
      weightG: Value(weightG),
      kcalPer100g: Value(kcalPer100g),
      proteinPer100g: Value(proteinPer100g),
      fatPer100g: Value(fatPer100g),
      carbsPer100g: Value(carbsPer100g),
      kcal: Value(kcal),
      protein: Value(protein),
      fat: Value(fat),
      carbs: Value(carbs),
      confidence: confidence == null && nullToAbsent
          ? const Value.absent()
          : Value(confidence),
      recognitionSource: recognitionSource == null && nullToAbsent
          ? const Value.absent()
          : Value(recognitionSource),
      wasCorrected: Value(wasCorrected),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory MealItemRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MealItemRow(
      id: serializer.fromJson<String>(json['id']),
      mealId: serializer.fromJson<String>(json['mealId']),
      foodId: serializer.fromJson<String?>(json['foodId']),
      name: serializer.fromJson<String>(json['name']),
      estimatedWeightG: serializer.fromJson<double?>(json['estimatedWeightG']),
      weightG: serializer.fromJson<double>(json['weightG']),
      kcalPer100g: serializer.fromJson<double>(json['kcalPer100g']),
      proteinPer100g: serializer.fromJson<double>(json['proteinPer100g']),
      fatPer100g: serializer.fromJson<double>(json['fatPer100g']),
      carbsPer100g: serializer.fromJson<double>(json['carbsPer100g']),
      kcal: serializer.fromJson<double>(json['kcal']),
      protein: serializer.fromJson<double>(json['protein']),
      fat: serializer.fromJson<double>(json['fat']),
      carbs: serializer.fromJson<double>(json['carbs']),
      confidence: serializer.fromJson<double?>(json['confidence']),
      recognitionSource: serializer.fromJson<String?>(
        json['recognitionSource'],
      ),
      wasCorrected: serializer.fromJson<bool>(json['wasCorrected']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'mealId': serializer.toJson<String>(mealId),
      'foodId': serializer.toJson<String?>(foodId),
      'name': serializer.toJson<String>(name),
      'estimatedWeightG': serializer.toJson<double?>(estimatedWeightG),
      'weightG': serializer.toJson<double>(weightG),
      'kcalPer100g': serializer.toJson<double>(kcalPer100g),
      'proteinPer100g': serializer.toJson<double>(proteinPer100g),
      'fatPer100g': serializer.toJson<double>(fatPer100g),
      'carbsPer100g': serializer.toJson<double>(carbsPer100g),
      'kcal': serializer.toJson<double>(kcal),
      'protein': serializer.toJson<double>(protein),
      'fat': serializer.toJson<double>(fat),
      'carbs': serializer.toJson<double>(carbs),
      'confidence': serializer.toJson<double?>(confidence),
      'recognitionSource': serializer.toJson<String?>(recognitionSource),
      'wasCorrected': serializer.toJson<bool>(wasCorrected),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  MealItemRow copyWith({
    String? id,
    String? mealId,
    Value<String?> foodId = const Value.absent(),
    String? name,
    Value<double?> estimatedWeightG = const Value.absent(),
    double? weightG,
    double? kcalPer100g,
    double? proteinPer100g,
    double? fatPer100g,
    double? carbsPer100g,
    double? kcal,
    double? protein,
    double? fat,
    double? carbs,
    Value<double?> confidence = const Value.absent(),
    Value<String?> recognitionSource = const Value.absent(),
    bool? wasCorrected,
    int? createdAt,
    int? updatedAt,
  }) => MealItemRow(
    id: id ?? this.id,
    mealId: mealId ?? this.mealId,
    foodId: foodId.present ? foodId.value : this.foodId,
    name: name ?? this.name,
    estimatedWeightG: estimatedWeightG.present
        ? estimatedWeightG.value
        : this.estimatedWeightG,
    weightG: weightG ?? this.weightG,
    kcalPer100g: kcalPer100g ?? this.kcalPer100g,
    proteinPer100g: proteinPer100g ?? this.proteinPer100g,
    fatPer100g: fatPer100g ?? this.fatPer100g,
    carbsPer100g: carbsPer100g ?? this.carbsPer100g,
    kcal: kcal ?? this.kcal,
    protein: protein ?? this.protein,
    fat: fat ?? this.fat,
    carbs: carbs ?? this.carbs,
    confidence: confidence.present ? confidence.value : this.confidence,
    recognitionSource: recognitionSource.present
        ? recognitionSource.value
        : this.recognitionSource,
    wasCorrected: wasCorrected ?? this.wasCorrected,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  MealItemRow copyWithCompanion(MealItemsCompanion data) {
    return MealItemRow(
      id: data.id.present ? data.id.value : this.id,
      mealId: data.mealId.present ? data.mealId.value : this.mealId,
      foodId: data.foodId.present ? data.foodId.value : this.foodId,
      name: data.name.present ? data.name.value : this.name,
      estimatedWeightG: data.estimatedWeightG.present
          ? data.estimatedWeightG.value
          : this.estimatedWeightG,
      weightG: data.weightG.present ? data.weightG.value : this.weightG,
      kcalPer100g: data.kcalPer100g.present
          ? data.kcalPer100g.value
          : this.kcalPer100g,
      proteinPer100g: data.proteinPer100g.present
          ? data.proteinPer100g.value
          : this.proteinPer100g,
      fatPer100g: data.fatPer100g.present
          ? data.fatPer100g.value
          : this.fatPer100g,
      carbsPer100g: data.carbsPer100g.present
          ? data.carbsPer100g.value
          : this.carbsPer100g,
      kcal: data.kcal.present ? data.kcal.value : this.kcal,
      protein: data.protein.present ? data.protein.value : this.protein,
      fat: data.fat.present ? data.fat.value : this.fat,
      carbs: data.carbs.present ? data.carbs.value : this.carbs,
      confidence: data.confidence.present
          ? data.confidence.value
          : this.confidence,
      recognitionSource: data.recognitionSource.present
          ? data.recognitionSource.value
          : this.recognitionSource,
      wasCorrected: data.wasCorrected.present
          ? data.wasCorrected.value
          : this.wasCorrected,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MealItemRow(')
          ..write('id: $id, ')
          ..write('mealId: $mealId, ')
          ..write('foodId: $foodId, ')
          ..write('name: $name, ')
          ..write('estimatedWeightG: $estimatedWeightG, ')
          ..write('weightG: $weightG, ')
          ..write('kcalPer100g: $kcalPer100g, ')
          ..write('proteinPer100g: $proteinPer100g, ')
          ..write('fatPer100g: $fatPer100g, ')
          ..write('carbsPer100g: $carbsPer100g, ')
          ..write('kcal: $kcal, ')
          ..write('protein: $protein, ')
          ..write('fat: $fat, ')
          ..write('carbs: $carbs, ')
          ..write('confidence: $confidence, ')
          ..write('recognitionSource: $recognitionSource, ')
          ..write('wasCorrected: $wasCorrected, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    mealId,
    foodId,
    name,
    estimatedWeightG,
    weightG,
    kcalPer100g,
    proteinPer100g,
    fatPer100g,
    carbsPer100g,
    kcal,
    protein,
    fat,
    carbs,
    confidence,
    recognitionSource,
    wasCorrected,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MealItemRow &&
          other.id == this.id &&
          other.mealId == this.mealId &&
          other.foodId == this.foodId &&
          other.name == this.name &&
          other.estimatedWeightG == this.estimatedWeightG &&
          other.weightG == this.weightG &&
          other.kcalPer100g == this.kcalPer100g &&
          other.proteinPer100g == this.proteinPer100g &&
          other.fatPer100g == this.fatPer100g &&
          other.carbsPer100g == this.carbsPer100g &&
          other.kcal == this.kcal &&
          other.protein == this.protein &&
          other.fat == this.fat &&
          other.carbs == this.carbs &&
          other.confidence == this.confidence &&
          other.recognitionSource == this.recognitionSource &&
          other.wasCorrected == this.wasCorrected &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class MealItemsCompanion extends UpdateCompanion<MealItemRow> {
  final Value<String> id;
  final Value<String> mealId;
  final Value<String?> foodId;
  final Value<String> name;
  final Value<double?> estimatedWeightG;
  final Value<double> weightG;
  final Value<double> kcalPer100g;
  final Value<double> proteinPer100g;
  final Value<double> fatPer100g;
  final Value<double> carbsPer100g;
  final Value<double> kcal;
  final Value<double> protein;
  final Value<double> fat;
  final Value<double> carbs;
  final Value<double?> confidence;
  final Value<String?> recognitionSource;
  final Value<bool> wasCorrected;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const MealItemsCompanion({
    this.id = const Value.absent(),
    this.mealId = const Value.absent(),
    this.foodId = const Value.absent(),
    this.name = const Value.absent(),
    this.estimatedWeightG = const Value.absent(),
    this.weightG = const Value.absent(),
    this.kcalPer100g = const Value.absent(),
    this.proteinPer100g = const Value.absent(),
    this.fatPer100g = const Value.absent(),
    this.carbsPer100g = const Value.absent(),
    this.kcal = const Value.absent(),
    this.protein = const Value.absent(),
    this.fat = const Value.absent(),
    this.carbs = const Value.absent(),
    this.confidence = const Value.absent(),
    this.recognitionSource = const Value.absent(),
    this.wasCorrected = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MealItemsCompanion.insert({
    required String id,
    required String mealId,
    this.foodId = const Value.absent(),
    required String name,
    this.estimatedWeightG = const Value.absent(),
    required double weightG,
    this.kcalPer100g = const Value.absent(),
    this.proteinPer100g = const Value.absent(),
    this.fatPer100g = const Value.absent(),
    this.carbsPer100g = const Value.absent(),
    this.kcal = const Value.absent(),
    this.protein = const Value.absent(),
    this.fat = const Value.absent(),
    this.carbs = const Value.absent(),
    this.confidence = const Value.absent(),
    this.recognitionSource = const Value.absent(),
    this.wasCorrected = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       mealId = Value(mealId),
       name = Value(name),
       weightG = Value(weightG),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<MealItemRow> custom({
    Expression<String>? id,
    Expression<String>? mealId,
    Expression<String>? foodId,
    Expression<String>? name,
    Expression<double>? estimatedWeightG,
    Expression<double>? weightG,
    Expression<double>? kcalPer100g,
    Expression<double>? proteinPer100g,
    Expression<double>? fatPer100g,
    Expression<double>? carbsPer100g,
    Expression<double>? kcal,
    Expression<double>? protein,
    Expression<double>? fat,
    Expression<double>? carbs,
    Expression<double>? confidence,
    Expression<String>? recognitionSource,
    Expression<bool>? wasCorrected,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (mealId != null) 'meal_id': mealId,
      if (foodId != null) 'food_id': foodId,
      if (name != null) 'name': name,
      if (estimatedWeightG != null) 'estimated_weight_g': estimatedWeightG,
      if (weightG != null) 'weight_g': weightG,
      if (kcalPer100g != null) 'kcal_per_100g': kcalPer100g,
      if (proteinPer100g != null) 'protein_per_100g': proteinPer100g,
      if (fatPer100g != null) 'fat_per_100g': fatPer100g,
      if (carbsPer100g != null) 'carbs_per_100g': carbsPer100g,
      if (kcal != null) 'kcal': kcal,
      if (protein != null) 'protein': protein,
      if (fat != null) 'fat': fat,
      if (carbs != null) 'carbs': carbs,
      if (confidence != null) 'confidence': confidence,
      if (recognitionSource != null) 'recognition_source': recognitionSource,
      if (wasCorrected != null) 'was_corrected': wasCorrected,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MealItemsCompanion copyWith({
    Value<String>? id,
    Value<String>? mealId,
    Value<String?>? foodId,
    Value<String>? name,
    Value<double?>? estimatedWeightG,
    Value<double>? weightG,
    Value<double>? kcalPer100g,
    Value<double>? proteinPer100g,
    Value<double>? fatPer100g,
    Value<double>? carbsPer100g,
    Value<double>? kcal,
    Value<double>? protein,
    Value<double>? fat,
    Value<double>? carbs,
    Value<double?>? confidence,
    Value<String?>? recognitionSource,
    Value<bool>? wasCorrected,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return MealItemsCompanion(
      id: id ?? this.id,
      mealId: mealId ?? this.mealId,
      foodId: foodId ?? this.foodId,
      name: name ?? this.name,
      estimatedWeightG: estimatedWeightG ?? this.estimatedWeightG,
      weightG: weightG ?? this.weightG,
      kcalPer100g: kcalPer100g ?? this.kcalPer100g,
      proteinPer100g: proteinPer100g ?? this.proteinPer100g,
      fatPer100g: fatPer100g ?? this.fatPer100g,
      carbsPer100g: carbsPer100g ?? this.carbsPer100g,
      kcal: kcal ?? this.kcal,
      protein: protein ?? this.protein,
      fat: fat ?? this.fat,
      carbs: carbs ?? this.carbs,
      confidence: confidence ?? this.confidence,
      recognitionSource: recognitionSource ?? this.recognitionSource,
      wasCorrected: wasCorrected ?? this.wasCorrected,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (mealId.present) {
      map['meal_id'] = Variable<String>(mealId.value);
    }
    if (foodId.present) {
      map['food_id'] = Variable<String>(foodId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (estimatedWeightG.present) {
      map['estimated_weight_g'] = Variable<double>(estimatedWeightG.value);
    }
    if (weightG.present) {
      map['weight_g'] = Variable<double>(weightG.value);
    }
    if (kcalPer100g.present) {
      map['kcal_per_100g'] = Variable<double>(kcalPer100g.value);
    }
    if (proteinPer100g.present) {
      map['protein_per_100g'] = Variable<double>(proteinPer100g.value);
    }
    if (fatPer100g.present) {
      map['fat_per_100g'] = Variable<double>(fatPer100g.value);
    }
    if (carbsPer100g.present) {
      map['carbs_per_100g'] = Variable<double>(carbsPer100g.value);
    }
    if (kcal.present) {
      map['kcal'] = Variable<double>(kcal.value);
    }
    if (protein.present) {
      map['protein'] = Variable<double>(protein.value);
    }
    if (fat.present) {
      map['fat'] = Variable<double>(fat.value);
    }
    if (carbs.present) {
      map['carbs'] = Variable<double>(carbs.value);
    }
    if (confidence.present) {
      map['confidence'] = Variable<double>(confidence.value);
    }
    if (recognitionSource.present) {
      map['recognition_source'] = Variable<String>(recognitionSource.value);
    }
    if (wasCorrected.present) {
      map['was_corrected'] = Variable<bool>(wasCorrected.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MealItemsCompanion(')
          ..write('id: $id, ')
          ..write('mealId: $mealId, ')
          ..write('foodId: $foodId, ')
          ..write('name: $name, ')
          ..write('estimatedWeightG: $estimatedWeightG, ')
          ..write('weightG: $weightG, ')
          ..write('kcalPer100g: $kcalPer100g, ')
          ..write('proteinPer100g: $proteinPer100g, ')
          ..write('fatPer100g: $fatPer100g, ')
          ..write('carbsPer100g: $carbsPer100g, ')
          ..write('kcal: $kcal, ')
          ..write('protein: $protein, ')
          ..write('fat: $fat, ')
          ..write('carbs: $carbs, ')
          ..write('confidence: $confidence, ')
          ..write('recognitionSource: $recognitionSource, ')
          ..write('wasCorrected: $wasCorrected, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FoodsTable extends Foods with TableInfo<$FoodsTable, FoodRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FoodsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
  static const VerificationMeta _nameRuMeta = const VerificationMeta('nameRu');
  @override
  late final GeneratedColumn<String> nameRu = GeneratedColumn<String>(
    'name_ru',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _normalizedNameMeta = const VerificationMeta(
    'normalizedName',
  );
  @override
  late final GeneratedColumn<String> normalizedName = GeneratedColumn<String>(
    'normalized_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _aliasesMeta = const VerificationMeta(
    'aliases',
  );
  @override
  late final GeneratedColumn<String> aliases = GeneratedColumn<String>(
    'aliases',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _kcalPer100gMeta = const VerificationMeta(
    'kcalPer100g',
  );
  @override
  late final GeneratedColumn<double> kcalPer100g = GeneratedColumn<double>(
    'kcal_per_100g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _proteinPer100gMeta = const VerificationMeta(
    'proteinPer100g',
  );
  @override
  late final GeneratedColumn<double> proteinPer100g = GeneratedColumn<double>(
    'protein_per_100g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _fatPer100gMeta = const VerificationMeta(
    'fatPer100g',
  );
  @override
  late final GeneratedColumn<double> fatPer100g = GeneratedColumn<double>(
    'fat_per_100g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _carbsPer100gMeta = const VerificationMeta(
    'carbsPer100g',
  );
  @override
  late final GeneratedColumn<double> carbsPer100g = GeneratedColumn<double>(
    'carbs_per_100g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _gramsPerPieceMeta = const VerificationMeta(
    'gramsPerPiece',
  );
  @override
  late final GeneratedColumn<double> gramsPerPiece = GeneratedColumn<double>(
    'grams_per_piece',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _gramsPerPortionMeta = const VerificationMeta(
    'gramsPerPortion',
  );
  @override
  late final GeneratedColumn<double> gramsPerPortion = GeneratedColumn<double>(
    'grams_per_portion',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _densityGPerMlMeta = const VerificationMeta(
    'densityGPerMl',
  );
  @override
  late final GeneratedColumn<double> densityGPerMl = GeneratedColumn<double>(
    'density_g_per_ml',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    nameRu,
    normalizedName,
    aliases,
    kcalPer100g,
    proteinPer100g,
    fatPer100g,
    carbsPer100g,
    gramsPerPiece,
    gramsPerPortion,
    densityGPerMl,
    source,
    sourceId,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'foods';
  @override
  VerificationContext validateIntegrity(
    Insertable<FoodRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('name_ru')) {
      context.handle(
        _nameRuMeta,
        nameRu.isAcceptableOrUnknown(data['name_ru']!, _nameRuMeta),
      );
    }
    if (data.containsKey('normalized_name')) {
      context.handle(
        _normalizedNameMeta,
        normalizedName.isAcceptableOrUnknown(
          data['normalized_name']!,
          _normalizedNameMeta,
        ),
      );
    }
    if (data.containsKey('aliases')) {
      context.handle(
        _aliasesMeta,
        aliases.isAcceptableOrUnknown(data['aliases']!, _aliasesMeta),
      );
    }
    if (data.containsKey('kcal_per_100g')) {
      context.handle(
        _kcalPer100gMeta,
        kcalPer100g.isAcceptableOrUnknown(
          data['kcal_per_100g']!,
          _kcalPer100gMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_kcalPer100gMeta);
    }
    if (data.containsKey('protein_per_100g')) {
      context.handle(
        _proteinPer100gMeta,
        proteinPer100g.isAcceptableOrUnknown(
          data['protein_per_100g']!,
          _proteinPer100gMeta,
        ),
      );
    }
    if (data.containsKey('fat_per_100g')) {
      context.handle(
        _fatPer100gMeta,
        fatPer100g.isAcceptableOrUnknown(
          data['fat_per_100g']!,
          _fatPer100gMeta,
        ),
      );
    }
    if (data.containsKey('carbs_per_100g')) {
      context.handle(
        _carbsPer100gMeta,
        carbsPer100g.isAcceptableOrUnknown(
          data['carbs_per_100g']!,
          _carbsPer100gMeta,
        ),
      );
    }
    if (data.containsKey('grams_per_piece')) {
      context.handle(
        _gramsPerPieceMeta,
        gramsPerPiece.isAcceptableOrUnknown(
          data['grams_per_piece']!,
          _gramsPerPieceMeta,
        ),
      );
    }
    if (data.containsKey('grams_per_portion')) {
      context.handle(
        _gramsPerPortionMeta,
        gramsPerPortion.isAcceptableOrUnknown(
          data['grams_per_portion']!,
          _gramsPerPortionMeta,
        ),
      );
    }
    if (data.containsKey('density_g_per_ml')) {
      context.handle(
        _densityGPerMlMeta,
        densityGPerMl.isAcceptableOrUnknown(
          data['density_g_per_ml']!,
          _densityGPerMlMeta,
        ),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FoodRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FoodRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      nameRu: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_ru'],
      ),
      normalizedName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}normalized_name'],
      ),
      aliases: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}aliases'],
      ),
      kcalPer100g: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}kcal_per_100g'],
      )!,
      proteinPer100g: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}protein_per_100g'],
      )!,
      fatPer100g: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}fat_per_100g'],
      )!,
      carbsPer100g: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}carbs_per_100g'],
      )!,
      gramsPerPiece: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}grams_per_piece'],
      ),
      gramsPerPortion: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}grams_per_portion'],
      ),
      densityGPerMl: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}density_g_per_ml'],
      ),
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      ),
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $FoodsTable createAlias(String alias) {
    return $FoodsTable(attachedDatabase, alias);
  }
}

class FoodRow extends DataClass implements Insertable<FoodRow> {
  final String id;
  final String name;

  /// Russian display name (catalog foods).
  final String? nameRu;
  final String? normalizedName;

  /// Newline-separated aliases in both languages.
  final String? aliases;
  final double kcalPer100g;
  final double proteinPer100g;
  final double fatPer100g;
  final double carbsPer100g;
  final double? gramsPerPiece;
  final double? gramsPerPortion;
  final double? densityGPerMl;

  /// `catalog`, `ai_estimate` or `user`.
  final String? source;
  final String? sourceId;
  final int updatedAt;
  const FoodRow({
    required this.id,
    required this.name,
    this.nameRu,
    this.normalizedName,
    this.aliases,
    required this.kcalPer100g,
    required this.proteinPer100g,
    required this.fatPer100g,
    required this.carbsPer100g,
    this.gramsPerPiece,
    this.gramsPerPortion,
    this.densityGPerMl,
    this.source,
    this.sourceId,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || nameRu != null) {
      map['name_ru'] = Variable<String>(nameRu);
    }
    if (!nullToAbsent || normalizedName != null) {
      map['normalized_name'] = Variable<String>(normalizedName);
    }
    if (!nullToAbsent || aliases != null) {
      map['aliases'] = Variable<String>(aliases);
    }
    map['kcal_per_100g'] = Variable<double>(kcalPer100g);
    map['protein_per_100g'] = Variable<double>(proteinPer100g);
    map['fat_per_100g'] = Variable<double>(fatPer100g);
    map['carbs_per_100g'] = Variable<double>(carbsPer100g);
    if (!nullToAbsent || gramsPerPiece != null) {
      map['grams_per_piece'] = Variable<double>(gramsPerPiece);
    }
    if (!nullToAbsent || gramsPerPortion != null) {
      map['grams_per_portion'] = Variable<double>(gramsPerPortion);
    }
    if (!nullToAbsent || densityGPerMl != null) {
      map['density_g_per_ml'] = Variable<double>(densityGPerMl);
    }
    if (!nullToAbsent || source != null) {
      map['source'] = Variable<String>(source);
    }
    if (!nullToAbsent || sourceId != null) {
      map['source_id'] = Variable<String>(sourceId);
    }
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  FoodsCompanion toCompanion(bool nullToAbsent) {
    return FoodsCompanion(
      id: Value(id),
      name: Value(name),
      nameRu: nameRu == null && nullToAbsent
          ? const Value.absent()
          : Value(nameRu),
      normalizedName: normalizedName == null && nullToAbsent
          ? const Value.absent()
          : Value(normalizedName),
      aliases: aliases == null && nullToAbsent
          ? const Value.absent()
          : Value(aliases),
      kcalPer100g: Value(kcalPer100g),
      proteinPer100g: Value(proteinPer100g),
      fatPer100g: Value(fatPer100g),
      carbsPer100g: Value(carbsPer100g),
      gramsPerPiece: gramsPerPiece == null && nullToAbsent
          ? const Value.absent()
          : Value(gramsPerPiece),
      gramsPerPortion: gramsPerPortion == null && nullToAbsent
          ? const Value.absent()
          : Value(gramsPerPortion),
      densityGPerMl: densityGPerMl == null && nullToAbsent
          ? const Value.absent()
          : Value(densityGPerMl),
      source: source == null && nullToAbsent
          ? const Value.absent()
          : Value(source),
      sourceId: sourceId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceId),
      updatedAt: Value(updatedAt),
    );
  }

  factory FoodRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FoodRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      nameRu: serializer.fromJson<String?>(json['nameRu']),
      normalizedName: serializer.fromJson<String?>(json['normalizedName']),
      aliases: serializer.fromJson<String?>(json['aliases']),
      kcalPer100g: serializer.fromJson<double>(json['kcalPer100g']),
      proteinPer100g: serializer.fromJson<double>(json['proteinPer100g']),
      fatPer100g: serializer.fromJson<double>(json['fatPer100g']),
      carbsPer100g: serializer.fromJson<double>(json['carbsPer100g']),
      gramsPerPiece: serializer.fromJson<double?>(json['gramsPerPiece']),
      gramsPerPortion: serializer.fromJson<double?>(json['gramsPerPortion']),
      densityGPerMl: serializer.fromJson<double?>(json['densityGPerMl']),
      source: serializer.fromJson<String?>(json['source']),
      sourceId: serializer.fromJson<String?>(json['sourceId']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'nameRu': serializer.toJson<String?>(nameRu),
      'normalizedName': serializer.toJson<String?>(normalizedName),
      'aliases': serializer.toJson<String?>(aliases),
      'kcalPer100g': serializer.toJson<double>(kcalPer100g),
      'proteinPer100g': serializer.toJson<double>(proteinPer100g),
      'fatPer100g': serializer.toJson<double>(fatPer100g),
      'carbsPer100g': serializer.toJson<double>(carbsPer100g),
      'gramsPerPiece': serializer.toJson<double?>(gramsPerPiece),
      'gramsPerPortion': serializer.toJson<double?>(gramsPerPortion),
      'densityGPerMl': serializer.toJson<double?>(densityGPerMl),
      'source': serializer.toJson<String?>(source),
      'sourceId': serializer.toJson<String?>(sourceId),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  FoodRow copyWith({
    String? id,
    String? name,
    Value<String?> nameRu = const Value.absent(),
    Value<String?> normalizedName = const Value.absent(),
    Value<String?> aliases = const Value.absent(),
    double? kcalPer100g,
    double? proteinPer100g,
    double? fatPer100g,
    double? carbsPer100g,
    Value<double?> gramsPerPiece = const Value.absent(),
    Value<double?> gramsPerPortion = const Value.absent(),
    Value<double?> densityGPerMl = const Value.absent(),
    Value<String?> source = const Value.absent(),
    Value<String?> sourceId = const Value.absent(),
    int? updatedAt,
  }) => FoodRow(
    id: id ?? this.id,
    name: name ?? this.name,
    nameRu: nameRu.present ? nameRu.value : this.nameRu,
    normalizedName: normalizedName.present
        ? normalizedName.value
        : this.normalizedName,
    aliases: aliases.present ? aliases.value : this.aliases,
    kcalPer100g: kcalPer100g ?? this.kcalPer100g,
    proteinPer100g: proteinPer100g ?? this.proteinPer100g,
    fatPer100g: fatPer100g ?? this.fatPer100g,
    carbsPer100g: carbsPer100g ?? this.carbsPer100g,
    gramsPerPiece: gramsPerPiece.present
        ? gramsPerPiece.value
        : this.gramsPerPiece,
    gramsPerPortion: gramsPerPortion.present
        ? gramsPerPortion.value
        : this.gramsPerPortion,
    densityGPerMl: densityGPerMl.present
        ? densityGPerMl.value
        : this.densityGPerMl,
    source: source.present ? source.value : this.source,
    sourceId: sourceId.present ? sourceId.value : this.sourceId,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  FoodRow copyWithCompanion(FoodsCompanion data) {
    return FoodRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      nameRu: data.nameRu.present ? data.nameRu.value : this.nameRu,
      normalizedName: data.normalizedName.present
          ? data.normalizedName.value
          : this.normalizedName,
      aliases: data.aliases.present ? data.aliases.value : this.aliases,
      kcalPer100g: data.kcalPer100g.present
          ? data.kcalPer100g.value
          : this.kcalPer100g,
      proteinPer100g: data.proteinPer100g.present
          ? data.proteinPer100g.value
          : this.proteinPer100g,
      fatPer100g: data.fatPer100g.present
          ? data.fatPer100g.value
          : this.fatPer100g,
      carbsPer100g: data.carbsPer100g.present
          ? data.carbsPer100g.value
          : this.carbsPer100g,
      gramsPerPiece: data.gramsPerPiece.present
          ? data.gramsPerPiece.value
          : this.gramsPerPiece,
      gramsPerPortion: data.gramsPerPortion.present
          ? data.gramsPerPortion.value
          : this.gramsPerPortion,
      densityGPerMl: data.densityGPerMl.present
          ? data.densityGPerMl.value
          : this.densityGPerMl,
      source: data.source.present ? data.source.value : this.source,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FoodRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('nameRu: $nameRu, ')
          ..write('normalizedName: $normalizedName, ')
          ..write('aliases: $aliases, ')
          ..write('kcalPer100g: $kcalPer100g, ')
          ..write('proteinPer100g: $proteinPer100g, ')
          ..write('fatPer100g: $fatPer100g, ')
          ..write('carbsPer100g: $carbsPer100g, ')
          ..write('gramsPerPiece: $gramsPerPiece, ')
          ..write('gramsPerPortion: $gramsPerPortion, ')
          ..write('densityGPerMl: $densityGPerMl, ')
          ..write('source: $source, ')
          ..write('sourceId: $sourceId, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    nameRu,
    normalizedName,
    aliases,
    kcalPer100g,
    proteinPer100g,
    fatPer100g,
    carbsPer100g,
    gramsPerPiece,
    gramsPerPortion,
    densityGPerMl,
    source,
    sourceId,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FoodRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.nameRu == this.nameRu &&
          other.normalizedName == this.normalizedName &&
          other.aliases == this.aliases &&
          other.kcalPer100g == this.kcalPer100g &&
          other.proteinPer100g == this.proteinPer100g &&
          other.fatPer100g == this.fatPer100g &&
          other.carbsPer100g == this.carbsPer100g &&
          other.gramsPerPiece == this.gramsPerPiece &&
          other.gramsPerPortion == this.gramsPerPortion &&
          other.densityGPerMl == this.densityGPerMl &&
          other.source == this.source &&
          other.sourceId == this.sourceId &&
          other.updatedAt == this.updatedAt);
}

class FoodsCompanion extends UpdateCompanion<FoodRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> nameRu;
  final Value<String?> normalizedName;
  final Value<String?> aliases;
  final Value<double> kcalPer100g;
  final Value<double> proteinPer100g;
  final Value<double> fatPer100g;
  final Value<double> carbsPer100g;
  final Value<double?> gramsPerPiece;
  final Value<double?> gramsPerPortion;
  final Value<double?> densityGPerMl;
  final Value<String?> source;
  final Value<String?> sourceId;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const FoodsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.nameRu = const Value.absent(),
    this.normalizedName = const Value.absent(),
    this.aliases = const Value.absent(),
    this.kcalPer100g = const Value.absent(),
    this.proteinPer100g = const Value.absent(),
    this.fatPer100g = const Value.absent(),
    this.carbsPer100g = const Value.absent(),
    this.gramsPerPiece = const Value.absent(),
    this.gramsPerPortion = const Value.absent(),
    this.densityGPerMl = const Value.absent(),
    this.source = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FoodsCompanion.insert({
    required String id,
    required String name,
    this.nameRu = const Value.absent(),
    this.normalizedName = const Value.absent(),
    this.aliases = const Value.absent(),
    required double kcalPer100g,
    this.proteinPer100g = const Value.absent(),
    this.fatPer100g = const Value.absent(),
    this.carbsPer100g = const Value.absent(),
    this.gramsPerPiece = const Value.absent(),
    this.gramsPerPortion = const Value.absent(),
    this.densityGPerMl = const Value.absent(),
    this.source = const Value.absent(),
    this.sourceId = const Value.absent(),
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       kcalPer100g = Value(kcalPer100g),
       updatedAt = Value(updatedAt);
  static Insertable<FoodRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? nameRu,
    Expression<String>? normalizedName,
    Expression<String>? aliases,
    Expression<double>? kcalPer100g,
    Expression<double>? proteinPer100g,
    Expression<double>? fatPer100g,
    Expression<double>? carbsPer100g,
    Expression<double>? gramsPerPiece,
    Expression<double>? gramsPerPortion,
    Expression<double>? densityGPerMl,
    Expression<String>? source,
    Expression<String>? sourceId,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (nameRu != null) 'name_ru': nameRu,
      if (normalizedName != null) 'normalized_name': normalizedName,
      if (aliases != null) 'aliases': aliases,
      if (kcalPer100g != null) 'kcal_per_100g': kcalPer100g,
      if (proteinPer100g != null) 'protein_per_100g': proteinPer100g,
      if (fatPer100g != null) 'fat_per_100g': fatPer100g,
      if (carbsPer100g != null) 'carbs_per_100g': carbsPer100g,
      if (gramsPerPiece != null) 'grams_per_piece': gramsPerPiece,
      if (gramsPerPortion != null) 'grams_per_portion': gramsPerPortion,
      if (densityGPerMl != null) 'density_g_per_ml': densityGPerMl,
      if (source != null) 'source': source,
      if (sourceId != null) 'source_id': sourceId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FoodsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String?>? nameRu,
    Value<String?>? normalizedName,
    Value<String?>? aliases,
    Value<double>? kcalPer100g,
    Value<double>? proteinPer100g,
    Value<double>? fatPer100g,
    Value<double>? carbsPer100g,
    Value<double?>? gramsPerPiece,
    Value<double?>? gramsPerPortion,
    Value<double?>? densityGPerMl,
    Value<String?>? source,
    Value<String?>? sourceId,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return FoodsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      nameRu: nameRu ?? this.nameRu,
      normalizedName: normalizedName ?? this.normalizedName,
      aliases: aliases ?? this.aliases,
      kcalPer100g: kcalPer100g ?? this.kcalPer100g,
      proteinPer100g: proteinPer100g ?? this.proteinPer100g,
      fatPer100g: fatPer100g ?? this.fatPer100g,
      carbsPer100g: carbsPer100g ?? this.carbsPer100g,
      gramsPerPiece: gramsPerPiece ?? this.gramsPerPiece,
      gramsPerPortion: gramsPerPortion ?? this.gramsPerPortion,
      densityGPerMl: densityGPerMl ?? this.densityGPerMl,
      source: source ?? this.source,
      sourceId: sourceId ?? this.sourceId,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (nameRu.present) {
      map['name_ru'] = Variable<String>(nameRu.value);
    }
    if (normalizedName.present) {
      map['normalized_name'] = Variable<String>(normalizedName.value);
    }
    if (aliases.present) {
      map['aliases'] = Variable<String>(aliases.value);
    }
    if (kcalPer100g.present) {
      map['kcal_per_100g'] = Variable<double>(kcalPer100g.value);
    }
    if (proteinPer100g.present) {
      map['protein_per_100g'] = Variable<double>(proteinPer100g.value);
    }
    if (fatPer100g.present) {
      map['fat_per_100g'] = Variable<double>(fatPer100g.value);
    }
    if (carbsPer100g.present) {
      map['carbs_per_100g'] = Variable<double>(carbsPer100g.value);
    }
    if (gramsPerPiece.present) {
      map['grams_per_piece'] = Variable<double>(gramsPerPiece.value);
    }
    if (gramsPerPortion.present) {
      map['grams_per_portion'] = Variable<double>(gramsPerPortion.value);
    }
    if (densityGPerMl.present) {
      map['density_g_per_ml'] = Variable<double>(densityGPerMl.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FoodsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('nameRu: $nameRu, ')
          ..write('normalizedName: $normalizedName, ')
          ..write('aliases: $aliases, ')
          ..write('kcalPer100g: $kcalPer100g, ')
          ..write('proteinPer100g: $proteinPer100g, ')
          ..write('fatPer100g: $fatPer100g, ')
          ..write('carbsPer100g: $carbsPer100g, ')
          ..write('gramsPerPiece: $gramsPerPiece, ')
          ..write('gramsPerPortion: $gramsPerPortion, ')
          ..write('densityGPerMl: $densityGPerMl, ')
          ..write('source: $source, ')
          ..write('sourceId: $sourceId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UserSettingsTable extends UserSettings
    with TableInfo<$UserSettingsTable, SettingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UserSettingsTable(this.attachedDatabase, [this._alias]);
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
  static const String $name = 'user_settings';
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
  $UserSettingsTable createAlias(String alias) {
    return $UserSettingsTable(attachedDatabase, alias);
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

  UserSettingsCompanion toCompanion(bool nullToAbsent) {
    return UserSettingsCompanion(key: Value(key), value: Value(value));
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
  SettingRow copyWithCompanion(UserSettingsCompanion data) {
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

class UserSettingsCompanion extends UpdateCompanion<SettingRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const UserSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UserSettingsCompanion.insert({
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

  UserSettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return UserSettingsCompanion(
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
    return (StringBuffer('UserSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AiCorrectionsTable extends AiCorrections
    with TableInfo<$AiCorrectionsTable, AiCorrectionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AiCorrectionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _normalizedFoodNameMeta =
      const VerificationMeta('normalizedFoodName');
  @override
  late final GeneratedColumn<String> normalizedFoodName =
      GeneratedColumn<String>(
        'normalized_food_name',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _aiWeightGMeta = const VerificationMeta(
    'aiWeightG',
  );
  @override
  late final GeneratedColumn<double> aiWeightG = GeneratedColumn<double>(
    'ai_weight_g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userWeightGMeta = const VerificationMeta(
    'userWeightG',
  );
  @override
  late final GeneratedColumn<double> userWeightG = GeneratedColumn<double>(
    'user_weight_g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _aiProviderMeta = const VerificationMeta(
    'aiProvider',
  );
  @override
  late final GeneratedColumn<String> aiProvider = GeneratedColumn<String>(
    'ai_provider',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _aiModelMeta = const VerificationMeta(
    'aiModel',
  );
  @override
  late final GeneratedColumn<String> aiModel = GeneratedColumn<String>(
    'ai_model',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    normalizedFoodName,
    aiWeightG,
    userWeightG,
    aiProvider,
    aiModel,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ai_corrections';
  @override
  VerificationContext validateIntegrity(
    Insertable<AiCorrectionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('normalized_food_name')) {
      context.handle(
        _normalizedFoodNameMeta,
        normalizedFoodName.isAcceptableOrUnknown(
          data['normalized_food_name']!,
          _normalizedFoodNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_normalizedFoodNameMeta);
    }
    if (data.containsKey('ai_weight_g')) {
      context.handle(
        _aiWeightGMeta,
        aiWeightG.isAcceptableOrUnknown(data['ai_weight_g']!, _aiWeightGMeta),
      );
    } else if (isInserting) {
      context.missing(_aiWeightGMeta);
    }
    if (data.containsKey('user_weight_g')) {
      context.handle(
        _userWeightGMeta,
        userWeightG.isAcceptableOrUnknown(
          data['user_weight_g']!,
          _userWeightGMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_userWeightGMeta);
    }
    if (data.containsKey('ai_provider')) {
      context.handle(
        _aiProviderMeta,
        aiProvider.isAcceptableOrUnknown(data['ai_provider']!, _aiProviderMeta),
      );
    }
    if (data.containsKey('ai_model')) {
      context.handle(
        _aiModelMeta,
        aiModel.isAcceptableOrUnknown(data['ai_model']!, _aiModelMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AiCorrectionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AiCorrectionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      normalizedFoodName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}normalized_food_name'],
      )!,
      aiWeightG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}ai_weight_g'],
      )!,
      userWeightG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}user_weight_g'],
      )!,
      aiProvider: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ai_provider'],
      ),
      aiModel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ai_model'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $AiCorrectionsTable createAlias(String alias) {
    return $AiCorrectionsTable(attachedDatabase, alias);
  }
}

class AiCorrectionRow extends DataClass implements Insertable<AiCorrectionRow> {
  /// Equals the id of the corrected meal item.
  final String id;
  final String normalizedFoodName;
  final double aiWeightG;
  final double userWeightG;
  final String? aiProvider;
  final String? aiModel;
  final int createdAt;
  const AiCorrectionRow({
    required this.id,
    required this.normalizedFoodName,
    required this.aiWeightG,
    required this.userWeightG,
    this.aiProvider,
    this.aiModel,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['normalized_food_name'] = Variable<String>(normalizedFoodName);
    map['ai_weight_g'] = Variable<double>(aiWeightG);
    map['user_weight_g'] = Variable<double>(userWeightG);
    if (!nullToAbsent || aiProvider != null) {
      map['ai_provider'] = Variable<String>(aiProvider);
    }
    if (!nullToAbsent || aiModel != null) {
      map['ai_model'] = Variable<String>(aiModel);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  AiCorrectionsCompanion toCompanion(bool nullToAbsent) {
    return AiCorrectionsCompanion(
      id: Value(id),
      normalizedFoodName: Value(normalizedFoodName),
      aiWeightG: Value(aiWeightG),
      userWeightG: Value(userWeightG),
      aiProvider: aiProvider == null && nullToAbsent
          ? const Value.absent()
          : Value(aiProvider),
      aiModel: aiModel == null && nullToAbsent
          ? const Value.absent()
          : Value(aiModel),
      createdAt: Value(createdAt),
    );
  }

  factory AiCorrectionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AiCorrectionRow(
      id: serializer.fromJson<String>(json['id']),
      normalizedFoodName: serializer.fromJson<String>(
        json['normalizedFoodName'],
      ),
      aiWeightG: serializer.fromJson<double>(json['aiWeightG']),
      userWeightG: serializer.fromJson<double>(json['userWeightG']),
      aiProvider: serializer.fromJson<String?>(json['aiProvider']),
      aiModel: serializer.fromJson<String?>(json['aiModel']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'normalizedFoodName': serializer.toJson<String>(normalizedFoodName),
      'aiWeightG': serializer.toJson<double>(aiWeightG),
      'userWeightG': serializer.toJson<double>(userWeightG),
      'aiProvider': serializer.toJson<String?>(aiProvider),
      'aiModel': serializer.toJson<String?>(aiModel),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  AiCorrectionRow copyWith({
    String? id,
    String? normalizedFoodName,
    double? aiWeightG,
    double? userWeightG,
    Value<String?> aiProvider = const Value.absent(),
    Value<String?> aiModel = const Value.absent(),
    int? createdAt,
  }) => AiCorrectionRow(
    id: id ?? this.id,
    normalizedFoodName: normalizedFoodName ?? this.normalizedFoodName,
    aiWeightG: aiWeightG ?? this.aiWeightG,
    userWeightG: userWeightG ?? this.userWeightG,
    aiProvider: aiProvider.present ? aiProvider.value : this.aiProvider,
    aiModel: aiModel.present ? aiModel.value : this.aiModel,
    createdAt: createdAt ?? this.createdAt,
  );
  AiCorrectionRow copyWithCompanion(AiCorrectionsCompanion data) {
    return AiCorrectionRow(
      id: data.id.present ? data.id.value : this.id,
      normalizedFoodName: data.normalizedFoodName.present
          ? data.normalizedFoodName.value
          : this.normalizedFoodName,
      aiWeightG: data.aiWeightG.present ? data.aiWeightG.value : this.aiWeightG,
      userWeightG: data.userWeightG.present
          ? data.userWeightG.value
          : this.userWeightG,
      aiProvider: data.aiProvider.present
          ? data.aiProvider.value
          : this.aiProvider,
      aiModel: data.aiModel.present ? data.aiModel.value : this.aiModel,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AiCorrectionRow(')
          ..write('id: $id, ')
          ..write('normalizedFoodName: $normalizedFoodName, ')
          ..write('aiWeightG: $aiWeightG, ')
          ..write('userWeightG: $userWeightG, ')
          ..write('aiProvider: $aiProvider, ')
          ..write('aiModel: $aiModel, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    normalizedFoodName,
    aiWeightG,
    userWeightG,
    aiProvider,
    aiModel,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AiCorrectionRow &&
          other.id == this.id &&
          other.normalizedFoodName == this.normalizedFoodName &&
          other.aiWeightG == this.aiWeightG &&
          other.userWeightG == this.userWeightG &&
          other.aiProvider == this.aiProvider &&
          other.aiModel == this.aiModel &&
          other.createdAt == this.createdAt);
}

class AiCorrectionsCompanion extends UpdateCompanion<AiCorrectionRow> {
  final Value<String> id;
  final Value<String> normalizedFoodName;
  final Value<double> aiWeightG;
  final Value<double> userWeightG;
  final Value<String?> aiProvider;
  final Value<String?> aiModel;
  final Value<int> createdAt;
  final Value<int> rowid;
  const AiCorrectionsCompanion({
    this.id = const Value.absent(),
    this.normalizedFoodName = const Value.absent(),
    this.aiWeightG = const Value.absent(),
    this.userWeightG = const Value.absent(),
    this.aiProvider = const Value.absent(),
    this.aiModel = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AiCorrectionsCompanion.insert({
    required String id,
    required String normalizedFoodName,
    required double aiWeightG,
    required double userWeightG,
    this.aiProvider = const Value.absent(),
    this.aiModel = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       normalizedFoodName = Value(normalizedFoodName),
       aiWeightG = Value(aiWeightG),
       userWeightG = Value(userWeightG),
       createdAt = Value(createdAt);
  static Insertable<AiCorrectionRow> custom({
    Expression<String>? id,
    Expression<String>? normalizedFoodName,
    Expression<double>? aiWeightG,
    Expression<double>? userWeightG,
    Expression<String>? aiProvider,
    Expression<String>? aiModel,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (normalizedFoodName != null)
        'normalized_food_name': normalizedFoodName,
      if (aiWeightG != null) 'ai_weight_g': aiWeightG,
      if (userWeightG != null) 'user_weight_g': userWeightG,
      if (aiProvider != null) 'ai_provider': aiProvider,
      if (aiModel != null) 'ai_model': aiModel,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AiCorrectionsCompanion copyWith({
    Value<String>? id,
    Value<String>? normalizedFoodName,
    Value<double>? aiWeightG,
    Value<double>? userWeightG,
    Value<String?>? aiProvider,
    Value<String?>? aiModel,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return AiCorrectionsCompanion(
      id: id ?? this.id,
      normalizedFoodName: normalizedFoodName ?? this.normalizedFoodName,
      aiWeightG: aiWeightG ?? this.aiWeightG,
      userWeightG: userWeightG ?? this.userWeightG,
      aiProvider: aiProvider ?? this.aiProvider,
      aiModel: aiModel ?? this.aiModel,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (normalizedFoodName.present) {
      map['normalized_food_name'] = Variable<String>(normalizedFoodName.value);
    }
    if (aiWeightG.present) {
      map['ai_weight_g'] = Variable<double>(aiWeightG.value);
    }
    if (userWeightG.present) {
      map['user_weight_g'] = Variable<double>(userWeightG.value);
    }
    if (aiProvider.present) {
      map['ai_provider'] = Variable<String>(aiProvider.value);
    }
    if (aiModel.present) {
      map['ai_model'] = Variable<String>(aiModel.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AiCorrectionsCompanion(')
          ..write('id: $id, ')
          ..write('normalizedFoodName: $normalizedFoodName, ')
          ..write('aiWeightG: $aiWeightG, ')
          ..write('userWeightG: $userWeightG, ')
          ..write('aiProvider: $aiProvider, ')
          ..write('aiModel: $aiModel, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $MealsTable meals = $MealsTable(this);
  late final $MealItemsTable mealItems = $MealItemsTable(this);
  late final $FoodsTable foods = $FoodsTable(this);
  late final $UserSettingsTable userSettings = $UserSettingsTable(this);
  late final $AiCorrectionsTable aiCorrections = $AiCorrectionsTable(this);
  late final Index idxMealsMealTime = Index(
    'idx_meals_meal_time',
    'CREATE INDEX idx_meals_meal_time ON meals (meal_time)',
  );
  late final Index idxMealItemsMealId = Index(
    'idx_meal_items_meal_id',
    'CREATE INDEX idx_meal_items_meal_id ON meal_items (meal_id)',
  );
  late final Index idxFoodsNormalizedName = Index(
    'idx_foods_normalized_name',
    'CREATE INDEX idx_foods_normalized_name ON foods (normalized_name)',
  );
  late final Index idxCorrectionsFood = Index(
    'idx_corrections_food',
    'CREATE INDEX idx_corrections_food ON ai_corrections (normalized_food_name)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    meals,
    mealItems,
    foods,
    userSettings,
    aiCorrections,
    idxMealsMealTime,
    idxMealItemsMealId,
    idxFoodsNormalizedName,
    idxCorrectionsFood,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'meals',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('meal_items', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$MealsTableCreateCompanionBuilder = MealsCompanion Function({
  required String id,
  required int mealTime,
  Value<String?> mealType,
  Value<String?> photoPath,
  Value<double> totalKcal,
  Value<double> totalProtein,
  Value<double> totalFat,
  Value<double> totalCarbs,
  Value<String?> aiProvider,
  Value<String?> aiModel,
  required int createdAt,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$MealsTableUpdateCompanionBuilder = MealsCompanion Function({
  Value<String> id,
  Value<int> mealTime,
  Value<String?> mealType,
  Value<String?> photoPath,
  Value<double> totalKcal,
  Value<double> totalProtein,
  Value<double> totalFat,
  Value<double> totalCarbs,
  Value<String?> aiProvider,
  Value<String?> aiModel,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int> rowid,
});

final class $$MealsTableReferences
    extends BaseReferences<_$AppDatabase, $MealsTable, MealRow> {
  $$MealsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$MealItemsTable, List<MealItemRow>>
  _mealItemsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.mealItems,
    aliasName: 'meals__id__meal_items__meal_id',
  );

  $$MealItemsTableProcessedTableManager get mealItemsRefs {
    final manager = $$MealItemsTableTableManager(
      $_db,
      $_db.mealItems,
    ).filter((f) => f.mealId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_mealItemsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$MealsTableFilterComposer extends Composer<_$AppDatabase, $MealsTable> {
  $$MealsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get mealTime => $composableBuilder(
    column: $table.mealTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mealType => $composableBuilder(
    column: $table.mealType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get photoPath => $composableBuilder(
    column: $table.photoPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get totalKcal => $composableBuilder(
    column: $table.totalKcal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get totalProtein => $composableBuilder(
    column: $table.totalProtein,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get totalFat => $composableBuilder(
    column: $table.totalFat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get totalCarbs => $composableBuilder(
    column: $table.totalCarbs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get aiProvider => $composableBuilder(
    column: $table.aiProvider,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get aiModel => $composableBuilder(
    column: $table.aiModel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> mealItemsRefs(
    Expression<bool> Function($$MealItemsTableFilterComposer f) f,
  ) {
    final $$MealItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.mealItems,
      getReferencedColumn: (t) => t.mealId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MealItemsTableFilterComposer(
            $db: $db,
            $table: $db.mealItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MealsTableOrderingComposer
    extends Composer<_$AppDatabase, $MealsTable> {
  $$MealsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get mealTime => $composableBuilder(
    column: $table.mealTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mealType => $composableBuilder(
    column: $table.mealType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get photoPath => $composableBuilder(
    column: $table.photoPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get totalKcal => $composableBuilder(
    column: $table.totalKcal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get totalProtein => $composableBuilder(
    column: $table.totalProtein,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get totalFat => $composableBuilder(
    column: $table.totalFat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get totalCarbs => $composableBuilder(
    column: $table.totalCarbs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get aiProvider => $composableBuilder(
    column: $table.aiProvider,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get aiModel => $composableBuilder(
    column: $table.aiModel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MealsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MealsTable> {
  $$MealsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get mealTime =>
      $composableBuilder(column: $table.mealTime, builder: (column) => column);

  GeneratedColumn<String> get mealType =>
      $composableBuilder(column: $table.mealType, builder: (column) => column);

  GeneratedColumn<String> get photoPath =>
      $composableBuilder(column: $table.photoPath, builder: (column) => column);

  GeneratedColumn<double> get totalKcal =>
      $composableBuilder(column: $table.totalKcal, builder: (column) => column);

  GeneratedColumn<double> get totalProtein => $composableBuilder(
    column: $table.totalProtein,
    builder: (column) => column,
  );

  GeneratedColumn<double> get totalFat =>
      $composableBuilder(column: $table.totalFat, builder: (column) => column);

  GeneratedColumn<double> get totalCarbs => $composableBuilder(
    column: $table.totalCarbs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get aiProvider => $composableBuilder(
    column: $table.aiProvider,
    builder: (column) => column,
  );

  GeneratedColumn<String> get aiModel =>
      $composableBuilder(column: $table.aiModel, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> mealItemsRefs<T extends Object>(
    Expression<T> Function($$MealItemsTableAnnotationComposer a) f,
  ) {
    final $$MealItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.mealItems,
      getReferencedColumn: (t) => t.mealId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MealItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.mealItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MealsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MealsTable,
          MealRow,
          $$MealsTableFilterComposer,
          $$MealsTableOrderingComposer,
          $$MealsTableAnnotationComposer,
          $$MealsTableCreateCompanionBuilder,
          $$MealsTableUpdateCompanionBuilder,
          (MealRow, $$MealsTableReferences),
          MealRow,
          PrefetchHooks Function({bool mealItemsRefs})
        > {
  $$MealsTableTableManager(_$AppDatabase db, $MealsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MealsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MealsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MealsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> mealTime = const Value.absent(),
                Value<String?> mealType = const Value.absent(),
                Value<String?> photoPath = const Value.absent(),
                Value<double> totalKcal = const Value.absent(),
                Value<double> totalProtein = const Value.absent(),
                Value<double> totalFat = const Value.absent(),
                Value<double> totalCarbs = const Value.absent(),
                Value<String?> aiProvider = const Value.absent(),
                Value<String?> aiModel = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MealsCompanion(
                id: id,
                mealTime: mealTime,
                mealType: mealType,
                photoPath: photoPath,
                totalKcal: totalKcal,
                totalProtein: totalProtein,
                totalFat: totalFat,
                totalCarbs: totalCarbs,
                aiProvider: aiProvider,
                aiModel: aiModel,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required int mealTime,
                Value<String?> mealType = const Value.absent(),
                Value<String?> photoPath = const Value.absent(),
                Value<double> totalKcal = const Value.absent(),
                Value<double> totalProtein = const Value.absent(),
                Value<double> totalFat = const Value.absent(),
                Value<double> totalCarbs = const Value.absent(),
                Value<String?> aiProvider = const Value.absent(),
                Value<String?> aiModel = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => MealsCompanion.insert(
                id: id,
                mealTime: mealTime,
                mealType: mealType,
                photoPath: photoPath,
                totalKcal: totalKcal,
                totalProtein: totalProtein,
                totalFat: totalFat,
                totalCarbs: totalCarbs,
                aiProvider: aiProvider,
                aiModel: aiModel,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MealsTable, MealRow>(table),
                  $$MealsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({mealItemsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (mealItemsRefs) db.mealItems],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (mealItemsRefs)
                    await $_getPrefetchedData<
                      MealRow,
                      $MealsTable,
                      MealItemRow
                    >(
                      currentTable: table,
                      referencedTable: $$MealsTableReferences
                          ._mealItemsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$MealsTableReferences(db, table, p0).mealItemsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.mealId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$MealsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MealsTable,
      MealRow,
      $$MealsTableFilterComposer,
      $$MealsTableOrderingComposer,
      $$MealsTableAnnotationComposer,
      $$MealsTableCreateCompanionBuilder,
      $$MealsTableUpdateCompanionBuilder,
      (MealRow, $$MealsTableReferences),
      MealRow,
      PrefetchHooks Function({bool mealItemsRefs})
    >;
typedef $$MealItemsTableCreateCompanionBuilder = MealItemsCompanion Function({
  required String id,
  required String mealId,
  Value<String?> foodId,
  required String name,
  Value<double?> estimatedWeightG,
  required double weightG,
  Value<double> kcalPer100g,
  Value<double> proteinPer100g,
  Value<double> fatPer100g,
  Value<double> carbsPer100g,
  Value<double> kcal,
  Value<double> protein,
  Value<double> fat,
  Value<double> carbs,
  Value<double?> confidence,
  Value<String?> recognitionSource,
  Value<bool> wasCorrected,
  required int createdAt,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$MealItemsTableUpdateCompanionBuilder = MealItemsCompanion Function({
  Value<String> id,
  Value<String> mealId,
  Value<String?> foodId,
  Value<String> name,
  Value<double?> estimatedWeightG,
  Value<double> weightG,
  Value<double> kcalPer100g,
  Value<double> proteinPer100g,
  Value<double> fatPer100g,
  Value<double> carbsPer100g,
  Value<double> kcal,
  Value<double> protein,
  Value<double> fat,
  Value<double> carbs,
  Value<double?> confidence,
  Value<String?> recognitionSource,
  Value<bool> wasCorrected,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int> rowid,
});

final class $$MealItemsTableReferences
    extends BaseReferences<_$AppDatabase, $MealItemsTable, MealItemRow> {
  $$MealItemsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $MealsTable _mealIdTable(_$AppDatabase db) =>
      db.meals.createAlias('meal_items__meal_id__meals__id');

  $$MealsTableProcessedTableManager get mealId {
    final $_column = $_itemColumn<String>('meal_id')!;

    final manager = $$MealsTableTableManager(
      $_db,
      $_db.meals,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_mealIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$MealItemsTableFilterComposer
    extends Composer<_$AppDatabase, $MealItemsTable> {
  $$MealItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get foodId => $composableBuilder(
    column: $table.foodId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get estimatedWeightG => $composableBuilder(
    column: $table.estimatedWeightG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get weightG => $composableBuilder(
    column: $table.weightG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get kcalPer100g => $composableBuilder(
    column: $table.kcalPer100g,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get proteinPer100g => $composableBuilder(
    column: $table.proteinPer100g,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get fatPer100g => $composableBuilder(
    column: $table.fatPer100g,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get carbsPer100g => $composableBuilder(
    column: $table.carbsPer100g,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get kcal => $composableBuilder(
    column: $table.kcal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get protein => $composableBuilder(
    column: $table.protein,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get fat => $composableBuilder(
    column: $table.fat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get carbs => $composableBuilder(
    column: $table.carbs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recognitionSource => $composableBuilder(
    column: $table.recognitionSource,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get wasCorrected => $composableBuilder(
    column: $table.wasCorrected,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$MealsTableFilterComposer get mealId {
    final $$MealsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.mealId,
      referencedTable: $db.meals,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MealsTableFilterComposer(
            $db: $db,
            $table: $db.meals,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MealItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $MealItemsTable> {
  $$MealItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get foodId => $composableBuilder(
    column: $table.foodId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get estimatedWeightG => $composableBuilder(
    column: $table.estimatedWeightG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get weightG => $composableBuilder(
    column: $table.weightG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get kcalPer100g => $composableBuilder(
    column: $table.kcalPer100g,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get proteinPer100g => $composableBuilder(
    column: $table.proteinPer100g,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get fatPer100g => $composableBuilder(
    column: $table.fatPer100g,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get carbsPer100g => $composableBuilder(
    column: $table.carbsPer100g,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get kcal => $composableBuilder(
    column: $table.kcal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get protein => $composableBuilder(
    column: $table.protein,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get fat => $composableBuilder(
    column: $table.fat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get carbs => $composableBuilder(
    column: $table.carbs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recognitionSource => $composableBuilder(
    column: $table.recognitionSource,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get wasCorrected => $composableBuilder(
    column: $table.wasCorrected,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$MealsTableOrderingComposer get mealId {
    final $$MealsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.mealId,
      referencedTable: $db.meals,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MealsTableOrderingComposer(
            $db: $db,
            $table: $db.meals,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MealItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MealItemsTable> {
  $$MealItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get foodId =>
      $composableBuilder(column: $table.foodId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<double> get estimatedWeightG => $composableBuilder(
    column: $table.estimatedWeightG,
    builder: (column) => column,
  );

  GeneratedColumn<double> get weightG =>
      $composableBuilder(column: $table.weightG, builder: (column) => column);

  GeneratedColumn<double> get kcalPer100g => $composableBuilder(
    column: $table.kcalPer100g,
    builder: (column) => column,
  );

  GeneratedColumn<double> get proteinPer100g => $composableBuilder(
    column: $table.proteinPer100g,
    builder: (column) => column,
  );

  GeneratedColumn<double> get fatPer100g => $composableBuilder(
    column: $table.fatPer100g,
    builder: (column) => column,
  );

  GeneratedColumn<double> get carbsPer100g => $composableBuilder(
    column: $table.carbsPer100g,
    builder: (column) => column,
  );

  GeneratedColumn<double> get kcal =>
      $composableBuilder(column: $table.kcal, builder: (column) => column);

  GeneratedColumn<double> get protein =>
      $composableBuilder(column: $table.protein, builder: (column) => column);

  GeneratedColumn<double> get fat =>
      $composableBuilder(column: $table.fat, builder: (column) => column);

  GeneratedColumn<double> get carbs =>
      $composableBuilder(column: $table.carbs, builder: (column) => column);

  GeneratedColumn<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => column,
  );

  GeneratedColumn<String> get recognitionSource => $composableBuilder(
    column: $table.recognitionSource,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get wasCorrected => $composableBuilder(
    column: $table.wasCorrected,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$MealsTableAnnotationComposer get mealId {
    final $$MealsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.mealId,
      referencedTable: $db.meals,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MealsTableAnnotationComposer(
            $db: $db,
            $table: $db.meals,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MealItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MealItemsTable,
          MealItemRow,
          $$MealItemsTableFilterComposer,
          $$MealItemsTableOrderingComposer,
          $$MealItemsTableAnnotationComposer,
          $$MealItemsTableCreateCompanionBuilder,
          $$MealItemsTableUpdateCompanionBuilder,
          (MealItemRow, $$MealItemsTableReferences),
          MealItemRow,
          PrefetchHooks Function({bool mealId})
        > {
  $$MealItemsTableTableManager(_$AppDatabase db, $MealItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MealItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MealItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MealItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> mealId = const Value.absent(),
                Value<String?> foodId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<double?> estimatedWeightG = const Value.absent(),
                Value<double> weightG = const Value.absent(),
                Value<double> kcalPer100g = const Value.absent(),
                Value<double> proteinPer100g = const Value.absent(),
                Value<double> fatPer100g = const Value.absent(),
                Value<double> carbsPer100g = const Value.absent(),
                Value<double> kcal = const Value.absent(),
                Value<double> protein = const Value.absent(),
                Value<double> fat = const Value.absent(),
                Value<double> carbs = const Value.absent(),
                Value<double?> confidence = const Value.absent(),
                Value<String?> recognitionSource = const Value.absent(),
                Value<bool> wasCorrected = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MealItemsCompanion(
                id: id,
                mealId: mealId,
                foodId: foodId,
                name: name,
                estimatedWeightG: estimatedWeightG,
                weightG: weightG,
                kcalPer100g: kcalPer100g,
                proteinPer100g: proteinPer100g,
                fatPer100g: fatPer100g,
                carbsPer100g: carbsPer100g,
                kcal: kcal,
                protein: protein,
                fat: fat,
                carbs: carbs,
                confidence: confidence,
                recognitionSource: recognitionSource,
                wasCorrected: wasCorrected,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String mealId,
                Value<String?> foodId = const Value.absent(),
                required String name,
                Value<double?> estimatedWeightG = const Value.absent(),
                required double weightG,
                Value<double> kcalPer100g = const Value.absent(),
                Value<double> proteinPer100g = const Value.absent(),
                Value<double> fatPer100g = const Value.absent(),
                Value<double> carbsPer100g = const Value.absent(),
                Value<double> kcal = const Value.absent(),
                Value<double> protein = const Value.absent(),
                Value<double> fat = const Value.absent(),
                Value<double> carbs = const Value.absent(),
                Value<double?> confidence = const Value.absent(),
                Value<String?> recognitionSource = const Value.absent(),
                Value<bool> wasCorrected = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => MealItemsCompanion.insert(
                id: id,
                mealId: mealId,
                foodId: foodId,
                name: name,
                estimatedWeightG: estimatedWeightG,
                weightG: weightG,
                kcalPer100g: kcalPer100g,
                proteinPer100g: proteinPer100g,
                fatPer100g: fatPer100g,
                carbsPer100g: carbsPer100g,
                kcal: kcal,
                protein: protein,
                fat: fat,
                carbs: carbs,
                confidence: confidence,
                recognitionSource: recognitionSource,
                wasCorrected: wasCorrected,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MealItemsTable, MealItemRow>(table),
                  $$MealItemsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({mealId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (mealId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.mealId,
                        referencedTable: $$MealItemsTableReferences
                            ._mealIdTable(db),
                        referencedColumn: $$MealItemsTableReferences
                            ._mealIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$MealItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MealItemsTable,
      MealItemRow,
      $$MealItemsTableFilterComposer,
      $$MealItemsTableOrderingComposer,
      $$MealItemsTableAnnotationComposer,
      $$MealItemsTableCreateCompanionBuilder,
      $$MealItemsTableUpdateCompanionBuilder,
      (MealItemRow, $$MealItemsTableReferences),
      MealItemRow,
      PrefetchHooks Function({bool mealId})
    >;
typedef $$FoodsTableCreateCompanionBuilder = FoodsCompanion Function({
  required String id,
  required String name,
  Value<String?> nameRu,
  Value<String?> normalizedName,
  Value<String?> aliases,
  required double kcalPer100g,
  Value<double> proteinPer100g,
  Value<double> fatPer100g,
  Value<double> carbsPer100g,
  Value<double?> gramsPerPiece,
  Value<double?> gramsPerPortion,
  Value<double?> densityGPerMl,
  Value<String?> source,
  Value<String?> sourceId,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$FoodsTableUpdateCompanionBuilder = FoodsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String?> nameRu,
  Value<String?> normalizedName,
  Value<String?> aliases,
  Value<double> kcalPer100g,
  Value<double> proteinPer100g,
  Value<double> fatPer100g,
  Value<double> carbsPer100g,
  Value<double?> gramsPerPiece,
  Value<double?> gramsPerPortion,
  Value<double?> densityGPerMl,
  Value<String?> source,
  Value<String?> sourceId,
  Value<int> updatedAt,
  Value<int> rowid,
});

class $$FoodsTableFilterComposer extends Composer<_$AppDatabase, $FoodsTable> {
  $$FoodsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nameRu => $composableBuilder(
    column: $table.nameRu,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get normalizedName => $composableBuilder(
    column: $table.normalizedName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get aliases => $composableBuilder(
    column: $table.aliases,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get kcalPer100g => $composableBuilder(
    column: $table.kcalPer100g,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get proteinPer100g => $composableBuilder(
    column: $table.proteinPer100g,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get fatPer100g => $composableBuilder(
    column: $table.fatPer100g,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get carbsPer100g => $composableBuilder(
    column: $table.carbsPer100g,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get gramsPerPiece => $composableBuilder(
    column: $table.gramsPerPiece,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get gramsPerPortion => $composableBuilder(
    column: $table.gramsPerPortion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get densityGPerMl => $composableBuilder(
    column: $table.densityGPerMl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FoodsTableOrderingComposer
    extends Composer<_$AppDatabase, $FoodsTable> {
  $$FoodsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nameRu => $composableBuilder(
    column: $table.nameRu,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get normalizedName => $composableBuilder(
    column: $table.normalizedName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get aliases => $composableBuilder(
    column: $table.aliases,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get kcalPer100g => $composableBuilder(
    column: $table.kcalPer100g,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get proteinPer100g => $composableBuilder(
    column: $table.proteinPer100g,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get fatPer100g => $composableBuilder(
    column: $table.fatPer100g,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get carbsPer100g => $composableBuilder(
    column: $table.carbsPer100g,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get gramsPerPiece => $composableBuilder(
    column: $table.gramsPerPiece,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get gramsPerPortion => $composableBuilder(
    column: $table.gramsPerPortion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get densityGPerMl => $composableBuilder(
    column: $table.densityGPerMl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FoodsTableAnnotationComposer
    extends Composer<_$AppDatabase, $FoodsTable> {
  $$FoodsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get nameRu =>
      $composableBuilder(column: $table.nameRu, builder: (column) => column);

  GeneratedColumn<String> get normalizedName => $composableBuilder(
    column: $table.normalizedName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get aliases =>
      $composableBuilder(column: $table.aliases, builder: (column) => column);

  GeneratedColumn<double> get kcalPer100g => $composableBuilder(
    column: $table.kcalPer100g,
    builder: (column) => column,
  );

  GeneratedColumn<double> get proteinPer100g => $composableBuilder(
    column: $table.proteinPer100g,
    builder: (column) => column,
  );

  GeneratedColumn<double> get fatPer100g => $composableBuilder(
    column: $table.fatPer100g,
    builder: (column) => column,
  );

  GeneratedColumn<double> get carbsPer100g => $composableBuilder(
    column: $table.carbsPer100g,
    builder: (column) => column,
  );

  GeneratedColumn<double> get gramsPerPiece => $composableBuilder(
    column: $table.gramsPerPiece,
    builder: (column) => column,
  );

  GeneratedColumn<double> get gramsPerPortion => $composableBuilder(
    column: $table.gramsPerPortion,
    builder: (column) => column,
  );

  GeneratedColumn<double> get densityGPerMl => $composableBuilder(
    column: $table.densityGPerMl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$FoodsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FoodsTable,
          FoodRow,
          $$FoodsTableFilterComposer,
          $$FoodsTableOrderingComposer,
          $$FoodsTableAnnotationComposer,
          $$FoodsTableCreateCompanionBuilder,
          $$FoodsTableUpdateCompanionBuilder,
          (FoodRow, BaseReferences<_$AppDatabase, $FoodsTable, FoodRow>),
          FoodRow,
          PrefetchHooks Function()
        > {
  $$FoodsTableTableManager(_$AppDatabase db, $FoodsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FoodsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FoodsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FoodsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> nameRu = const Value.absent(),
                Value<String?> normalizedName = const Value.absent(),
                Value<String?> aliases = const Value.absent(),
                Value<double> kcalPer100g = const Value.absent(),
                Value<double> proteinPer100g = const Value.absent(),
                Value<double> fatPer100g = const Value.absent(),
                Value<double> carbsPer100g = const Value.absent(),
                Value<double?> gramsPerPiece = const Value.absent(),
                Value<double?> gramsPerPortion = const Value.absent(),
                Value<double?> densityGPerMl = const Value.absent(),
                Value<String?> source = const Value.absent(),
                Value<String?> sourceId = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FoodsCompanion(
                id: id,
                name: name,
                nameRu: nameRu,
                normalizedName: normalizedName,
                aliases: aliases,
                kcalPer100g: kcalPer100g,
                proteinPer100g: proteinPer100g,
                fatPer100g: fatPer100g,
                carbsPer100g: carbsPer100g,
                gramsPerPiece: gramsPerPiece,
                gramsPerPortion: gramsPerPortion,
                densityGPerMl: densityGPerMl,
                source: source,
                sourceId: sourceId,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String?> nameRu = const Value.absent(),
                Value<String?> normalizedName = const Value.absent(),
                Value<String?> aliases = const Value.absent(),
                required double kcalPer100g,
                Value<double> proteinPer100g = const Value.absent(),
                Value<double> fatPer100g = const Value.absent(),
                Value<double> carbsPer100g = const Value.absent(),
                Value<double?> gramsPerPiece = const Value.absent(),
                Value<double?> gramsPerPortion = const Value.absent(),
                Value<double?> densityGPerMl = const Value.absent(),
                Value<String?> source = const Value.absent(),
                Value<String?> sourceId = const Value.absent(),
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => FoodsCompanion.insert(
                id: id,
                name: name,
                nameRu: nameRu,
                normalizedName: normalizedName,
                aliases: aliases,
                kcalPer100g: kcalPer100g,
                proteinPer100g: proteinPer100g,
                fatPer100g: fatPer100g,
                carbsPer100g: carbsPer100g,
                gramsPerPiece: gramsPerPiece,
                gramsPerPortion: gramsPerPortion,
                densityGPerMl: densityGPerMl,
                source: source,
                sourceId: sourceId,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FoodsTable, FoodRow>(table),
                  BaseReferences<_$AppDatabase, $FoodsTable, FoodRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FoodsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FoodsTable,
      FoodRow,
      $$FoodsTableFilterComposer,
      $$FoodsTableOrderingComposer,
      $$FoodsTableAnnotationComposer,
      $$FoodsTableCreateCompanionBuilder,
      $$FoodsTableUpdateCompanionBuilder,
      (FoodRow, BaseReferences<_$AppDatabase, $FoodsTable, FoodRow>),
      FoodRow,
      PrefetchHooks Function()
    >;
typedef $$UserSettingsTableCreateCompanionBuilder =
    UserSettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$UserSettingsTableUpdateCompanionBuilder =
    UserSettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$UserSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $UserSettingsTable> {
  $$UserSettingsTableFilterComposer({
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

class $$UserSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $UserSettingsTable> {
  $$UserSettingsTableOrderingComposer({
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

class $$UserSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $UserSettingsTable> {
  $$UserSettingsTableAnnotationComposer({
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

class $$UserSettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UserSettingsTable,
          SettingRow,
          $$UserSettingsTableFilterComposer,
          $$UserSettingsTableOrderingComposer,
          $$UserSettingsTableAnnotationComposer,
          $$UserSettingsTableCreateCompanionBuilder,
          $$UserSettingsTableUpdateCompanionBuilder,
          (
            SettingRow,
            BaseReferences<_$AppDatabase, $UserSettingsTable, SettingRow>,
          ),
          SettingRow,
          PrefetchHooks Function()
        > {
  $$UserSettingsTableTableManager(_$AppDatabase db, $UserSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UserSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UserSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UserSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => UserSettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => UserSettingsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$UserSettingsTable, SettingRow>(table),
                  BaseReferences<_$AppDatabase, $UserSettingsTable, SettingRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UserSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UserSettingsTable,
      SettingRow,
      $$UserSettingsTableFilterComposer,
      $$UserSettingsTableOrderingComposer,
      $$UserSettingsTableAnnotationComposer,
      $$UserSettingsTableCreateCompanionBuilder,
      $$UserSettingsTableUpdateCompanionBuilder,
      (
        SettingRow,
        BaseReferences<_$AppDatabase, $UserSettingsTable, SettingRow>,
      ),
      SettingRow,
      PrefetchHooks Function()
    >;
typedef $$AiCorrectionsTableCreateCompanionBuilder =
    AiCorrectionsCompanion Function({
      required String id,
      required String normalizedFoodName,
      required double aiWeightG,
      required double userWeightG,
      Value<String?> aiProvider,
      Value<String?> aiModel,
      required int createdAt,
      Value<int> rowid,
    });
typedef $$AiCorrectionsTableUpdateCompanionBuilder =
    AiCorrectionsCompanion Function({
      Value<String> id,
      Value<String> normalizedFoodName,
      Value<double> aiWeightG,
      Value<double> userWeightG,
      Value<String?> aiProvider,
      Value<String?> aiModel,
      Value<int> createdAt,
      Value<int> rowid,
    });

class $$AiCorrectionsTableFilterComposer
    extends Composer<_$AppDatabase, $AiCorrectionsTable> {
  $$AiCorrectionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get normalizedFoodName => $composableBuilder(
    column: $table.normalizedFoodName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get aiWeightG => $composableBuilder(
    column: $table.aiWeightG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get userWeightG => $composableBuilder(
    column: $table.userWeightG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get aiProvider => $composableBuilder(
    column: $table.aiProvider,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get aiModel => $composableBuilder(
    column: $table.aiModel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AiCorrectionsTableOrderingComposer
    extends Composer<_$AppDatabase, $AiCorrectionsTable> {
  $$AiCorrectionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get normalizedFoodName => $composableBuilder(
    column: $table.normalizedFoodName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get aiWeightG => $composableBuilder(
    column: $table.aiWeightG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get userWeightG => $composableBuilder(
    column: $table.userWeightG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get aiProvider => $composableBuilder(
    column: $table.aiProvider,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get aiModel => $composableBuilder(
    column: $table.aiModel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AiCorrectionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AiCorrectionsTable> {
  $$AiCorrectionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get normalizedFoodName => $composableBuilder(
    column: $table.normalizedFoodName,
    builder: (column) => column,
  );

  GeneratedColumn<double> get aiWeightG =>
      $composableBuilder(column: $table.aiWeightG, builder: (column) => column);

  GeneratedColumn<double> get userWeightG => $composableBuilder(
    column: $table.userWeightG,
    builder: (column) => column,
  );

  GeneratedColumn<String> get aiProvider => $composableBuilder(
    column: $table.aiProvider,
    builder: (column) => column,
  );

  GeneratedColumn<String> get aiModel =>
      $composableBuilder(column: $table.aiModel, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$AiCorrectionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AiCorrectionsTable,
          AiCorrectionRow,
          $$AiCorrectionsTableFilterComposer,
          $$AiCorrectionsTableOrderingComposer,
          $$AiCorrectionsTableAnnotationComposer,
          $$AiCorrectionsTableCreateCompanionBuilder,
          $$AiCorrectionsTableUpdateCompanionBuilder,
          (
            AiCorrectionRow,
            BaseReferences<_$AppDatabase, $AiCorrectionsTable, AiCorrectionRow>,
          ),
          AiCorrectionRow,
          PrefetchHooks Function()
        > {
  $$AiCorrectionsTableTableManager(_$AppDatabase db, $AiCorrectionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AiCorrectionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AiCorrectionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AiCorrectionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> normalizedFoodName = const Value.absent(),
                Value<double> aiWeightG = const Value.absent(),
                Value<double> userWeightG = const Value.absent(),
                Value<String?> aiProvider = const Value.absent(),
                Value<String?> aiModel = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AiCorrectionsCompanion(
                id: id,
                normalizedFoodName: normalizedFoodName,
                aiWeightG: aiWeightG,
                userWeightG: userWeightG,
                aiProvider: aiProvider,
                aiModel: aiModel,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String normalizedFoodName,
                required double aiWeightG,
                required double userWeightG,
                Value<String?> aiProvider = const Value.absent(),
                Value<String?> aiModel = const Value.absent(),
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => AiCorrectionsCompanion.insert(
                id: id,
                normalizedFoodName: normalizedFoodName,
                aiWeightG: aiWeightG,
                userWeightG: userWeightG,
                aiProvider: aiProvider,
                aiModel: aiModel,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AiCorrectionsTable, AiCorrectionRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $AiCorrectionsTable,
                    AiCorrectionRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AiCorrectionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AiCorrectionsTable,
      AiCorrectionRow,
      $$AiCorrectionsTableFilterComposer,
      $$AiCorrectionsTableOrderingComposer,
      $$AiCorrectionsTableAnnotationComposer,
      $$AiCorrectionsTableCreateCompanionBuilder,
      $$AiCorrectionsTableUpdateCompanionBuilder,
      (
        AiCorrectionRow,
        BaseReferences<_$AppDatabase, $AiCorrectionsTable, AiCorrectionRow>,
      ),
      AiCorrectionRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$MealsTableTableManager get meals =>
      $$MealsTableTableManager(_db, _db.meals);
  $$MealItemsTableTableManager get mealItems =>
      $$MealItemsTableTableManager(_db, _db.mealItems);
  $$FoodsTableTableManager get foods =>
      $$FoodsTableTableManager(_db, _db.foods);
  $$UserSettingsTableTableManager get userSettings =>
      $$UserSettingsTableTableManager(_db, _db.userSettings);
  $$AiCorrectionsTableTableManager get aiCorrections =>
      $$AiCorrectionsTableTableManager(_db, _db.aiCorrections);
}
