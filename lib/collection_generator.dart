import 'dart:developer' as developer;

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:code_builder/code_builder.dart';
import 'package:build/build.dart';
import 'package:sonicdb/utils.dart';
import 'package:source_gen/source_gen.dart';
import 'package:dart_style/dart_style.dart';
import 'package:sonicdb/annotation.dart';

class CollectionGenerator extends GeneratorForAnnotation<Collection> {
  static const String _varEntity = '_entity';

  // Collection<Entity> collectionAnnotation;

  @override
  String generateForAnnotatedElement(
      Element element, ConstantReader annotation, BuildStep buildStep) {
    // print("building element ${element.name} as Collection ");
    if (element is! ClassElement) {
      final name = element.displayName;
      throw InvalidGenerationSourceError(
        'Generator cannot target `$name`.',
        todo: 'Remove the [RestApi] annotation from `$name`.',
      );
    }

    return _implementClass(element, annotation);
  }

  String _implementClass(ClassElement element, ConstantReader annotation) {
    final className = element.name;
    final fields = element.fields;
    final methods = element.methods;

    final entity = annotation.peek('entity')?.typeValue;

    if (entity == null) {
      throw InvalidGenerationSourceError(
        'Generator cannot target `$className` because it doesn\'t have target entity.',
        todo:
            'Remove the [Collection] annotation from `$className` or define your entity.',
      );
    }
    // collectionAnnotation = Collection(
    //   entity: entity.runtimeType,
    // );

    final annotClassConsts = element.constructors
        .where((c) => !c.isFactory && !c.isDefaultConstructor);
    final classBuilder = Class((c) {
      c
        ..name = '${className}_collection'
        ..types.addAll(element.typeParameters.map((e) => refer(e.name)))
        ..fields.addAll([
          _buildEntityField(),
          ..._buildFields(
              fields.where((field) => isColumnField(field)).toList())
        ])
        ..methods.addAll(_buildMethods(methods
            .where((method) => isQueryMethod(method) || isInsertMethod(method))
            .toList()))
        ..constructors.addAll(
          annotClassConsts.map(
            (e) => _generateConstructor(entity, superClassConst: e),
          ),
        );
      // ..methods.addAll(_parseMethods(element));
      if (annotClassConsts.isEmpty) {
        c.constructors.add(_generateConstructor(entity));
        c.implements.add(refer(_generateTypeParameterizedName(element)));
      } else {
        c.extend = Reference(_generateTypeParameterizedName(element));
      }
    });
    final libraryBuilder = Library((b) {
      b.body.add(Code("import '${element.source.uri.toString()}';"));
      for (var lib in element.library.imports) {
        // print("CollectionGenerator : library source ${lib.uri}");
        b.body.add(Code("import '${lib.uri.toString()}';"));
      }
      b.body.add(classBuilder);
    });

    final emitter = DartEmitter();
    return DartFormatter().format('${libraryBuilder.accept(emitter)}');
  }

  Iterable<Method> _buildMethods(List<MethodElement> methods) {
    // List<Method> results = [];

    return methods.where((MethodElement m) {
      final methodAnnot = _getMethodAnnotation(m);
      // print("Collection : method annotations $methodAnnot");
      return methodAnnot != null && m.isAbstract; //&&
      // (m.returnType.isDartAsyncFuture || m.returnType.isDartAsyncStream);
    }).map((m) => _generateMethod(m));
    // for (var method in methods) {
    //   var meta = method.metadata;

    //   var queryMeta = meta.where((meta) => meta.toString().contains("@Query"));
    //   var isQueryMeta = queryMeta.length > 0;
    //   var parameters = method.parameters;
    //   print("Collection : parameters $parameters");
    //   final collectionMethod = _getMethodAnnotation(method);
    //   print("Collection : collection methods $collectionMethod");
    //   var queries = _getAnnotations(method, Query);
    //   print("Collection : queries $queries");
    //   // var query = annotation.stringValue;
    //   // .getDisplayString(withNullability: true);
    //   // print("Collection : query $query");
    //   results.add(Method(
    //     (m) => m
    //       ..name = method.name
    //       ..requiredParameters.addAll(_getRequiredParameters(method))
    //       ..optionalParameters.addAll(_getOptionalParameters(method))
    //       ..returns = Reference(method.returnType.toString())
    //       ..body = Code('''
    //           ${isQueryMeta ? "query" : ""}
    //     '''),
    //   ));
    // }

    // return results;
  }

  Method _generateMethod(MethodElement m) {
    print("building method ${m.name}");
    return Method((mm) {
      developer.log(
          "return types ${_displayString(m.type.returnType, withNullability: true)}");
      // if (isQueryMethod(m)) {
      mm
        ..returns =
            refer(_displayString(m.type.returnType, withNullability: true))
        ..name = m.displayName
        ..types.addAll(m.typeParameters.map((e) => refer(e.name)))
        ..modifier =
            m.returnType.isDartAsyncFuture ? MethodModifier.async : null
        ..annotations.add(CodeExpression(Code("override")));
      // }

      /// required parameters
      mm.requiredParameters.addAll(m.parameters
          .where((it) => it.isRequiredPositional || it.isRequiredNamed)
          .map((it) => Parameter((p) => p
            ..name = it.name
            ..type = p.type
            ..named = it.isNamed)));

      /// optional positional or named parameters
      mm.optionalParameters.addAll(m.parameters.where((i) => i.isOptional).map(
          (it) => Parameter((p) => p
            ..name = it.name
            ..named = it.isNamed
            ..type = p.type
            ..defaultTo = it.defaultValueCode == null
                ? null
                : Code(it.defaultValueCode!))));

      mm.body = _generateMethodBody(m);
    });
  }

  Code _generateMethodBody(MethodElement m) {
    var blocks = <Code>[
      Code("var db = this.db;"),
      Code("await db.open();"),
    ];

    if (isQueryMethod(m)) {
      var query = _getQuery(m);
      final queryArguments =
          query.split(" ").where((str) => str.startsWith(":"));

      queryArguments.forEach((arg) {
        String to = arg.replaceFirst(":", "\$");
        query = query.replaceAll(arg, to);
      });
      blocks.add(Code("var results = await db.query(${literal(query)});"));
      // print("collection method return type ${m.returnType}");
      if (_isFutureMethod(m)) {
        var typeString = _getFutureReturnType(m.returnType);

        if (_isListType(typeString)) {
          var dataType = _getListDataType(typeString);
          // print("list data type ${_getListDataType(typeString)}");
          blocks.addAll([
            Code("if(results is List) {"),
            Code("  var list = List.filled(0, null, growable: true);"),
            Code("  for(var item in results) {"),
            Code("    var listItem = ${dataType}_entity.fromMap(item);"),
            // Code("    for(var key in $_varEntity.keys) {"),
            // Code("      var fieldValue = $_varEntity[key];"),
            // Code("    }"),
            Code("  }"),
            Code("}"),
            // Code("return "),
          ]);
        }
      }
    } else if (isInsertMethod(m)) {
      var parameter =
          m.parameters.where((element) => element.isRequiredPositional).first;

      blocks.addAll([
        Code("var data = ${parameter.name}.toMap();"),
        // Code("return "),
      ]);
    }
    return Block.of(blocks);
  }

  bool _isSelectQuery(String query) {
    return query.toLowerCase().startsWith("select");
  }

  bool _isFutureMethod(MethodElement m) {
    return m.returnType.isDartAsyncFuture;
  }

  String _getFutureReturnType(DartType type) {
    return type
        .getDisplayString(withNullability: false)
        .replaceAll("Future<", "")
        .replaceAll(RegExp(">\$"), "");
  }

  String _getListDataType(dynamic type) {
    if (type is String) {
      return type.replaceAll("List<", "").replaceAll(RegExp(">\$"), "");
    } else if (type is DartType) {
      return type
          .getDisplayString(withNullability: false)
          .replaceAll("List<", "")
          .replaceAll(RegExp(">\$"), "");
    }
    return "";
  }

  bool _isListType(dynamic type) {
    if (type is String) {
      return type.startsWith("List");
    } else if (type is DartType) {
      return type.getDisplayString(withNullability: false).startsWith("List");
    }
    return false;
  }

  String _getQuery(MethodElement m) {
    var annotation = getAnnotation(m, Query);

    String definedQuery = annotation!.peek("query")!.stringValue;
    // print("Query :  $definedQuery");

    return definedQuery;
  }

  Expression _generateQuery(MethodElement m, ConstantReader method) {
    // final queries = _getAnnotations(m, Query);
    String definedQuery = method.peek("query")!.stringValue;
    // queries.forEach((k, v) {
    //   final value = v.peek("value")?.stringValue ?? k.displayName;
    //   definedQuery = definedQuery.re
    // })
    // print("Collection : defined query $definedQuery");
    return literal(definedQuery);
  }

  final _methodsAnnotations = const [Query, Insert, Update];

  ConstantReader? _getMethodAnnotation(MethodElement method) {
    for (final type in _methodsAnnotations) {
      final annot =
          typeChecker(type).firstAnnotationOf(method, throwOnUnresolved: false);
      if (annot != null) return ConstantReader(annot);
    }
    return null;
  }

  Iterable<Parameter> _getOptionalParameters(MethodElement method) {
    return method.parameters
        .where((element) => element.isOptional)
        .map((e) => Parameter((p) {
              p.name = e.name;
              p.type = Reference(e.type.toString());
            }));
  }

  Iterable<Parameter> _getRequiredParameters(MethodElement method) {
    return method.parameters
        .where((element) => element.isNotOptional)
        .map((e) => Parameter((p) {
              p.name = e.name;
              p.type = Reference(e.type.toString());
            }));
  }

  List<Field> _buildFields(List<FieldElement> fields) {
    List<Field> results = [];

    for (var field in fields) {
      ClassElement collectionClass = field.type.element as ClassElement;

      results.add(Field((m) => m
        ..name = field.name
        ..type = refer(collectionClass.name)
        ..modifier = FieldModifier.var$));
    }

    return results;
  }

  Constructor _generateConstructor(
    DartType entity, {
    ConstructorElement? superClassConst,
  }) =>
      Constructor((c) {
        // c.optionalParameters.add(Parameter((p) => p
        //   ..named = true
        //   ..name = _entity
        //   ..toThis = true));
        if (superClassConst != null) {
          var superConstName = 'super';
          if (superClassConst.name.isNotEmpty) {
            superConstName += '.${superClassConst.name}';
            c.name = superClassConst.name;
          }
          final constParams = superClassConst.parameters;
          constParams.forEach((element) {
            if (!element.isOptional || element.isPrivate) {
              c.requiredParameters.add(Parameter((p) => p
                ..type = refer(_displayString(element.type))
                ..name = element.name));
            } else {
              c.optionalParameters.add(Parameter((p) => p
                ..named = element.isNamed
                ..type = refer(_displayString(element.type))
                ..name = element.name));
            }
          });
          final paramList = constParams
              .map((e) => (e.isNamed ? '${e.name}: ' : '') + '${e.name}');
          c.initializers
              .add(Code('$superConstName(' + paramList.join(',') + ')'));
        }
        final block = <Code>[];

        // String varName = "entity${entity.element.name}";
        ClassElement entityClass = entity.element as ClassElement;
        var entityFields =
            entityClass.fields.where((field) => isColumnField(field));

        // block.add(Code("var $varName = Map();"));

        entityFields.forEach((field) {
          var typeString = getFieldSqlType(field);
          var varFieldInfo = "entity${entity.element!.name}_${field.name}";
          block.add(Code("var $varFieldInfo = Map();"));
          field.metadata.forEach((metadata) {
            var meta = ConstantReader(metadata.computeConstantValue());
            if (meta.instanceOf(typeChecker(PrimaryKey))) {
              var autoGenerated =
                  meta.peek("autoGenerated")?.boolValue ?? false;
              block
                  .add(Code("$varFieldInfo[${literal("primaryKey")}] = true;"));
              block.add(Code(
                  "$varFieldInfo[${literal("autoGenerated")}] = $autoGenerated;"));
            } else if (meta.instanceOf(typeChecker(ColumnInfo))) {
              // print(
              //     "meta field is column ${meta.instanceOf(typeChecker(ColumnInfo))}");
              var columnName = meta.peek("name")?.stringValue ?? field.name;
              var type = meta.peek("type")?.stringValue ?? typeString;
              block.add(Code(
                  "$varFieldInfo[${literal("name")}] = ${literal(columnName)};"));
              block.add(Code(
                  "$varFieldInfo[${literal("type")}] = ${literal(type)};"));
            }
          });
          block.add(
              Code("$_varEntity[${literal(field.name)}] = $varFieldInfo;"));
        });

        // block.add(Code("$_varEntity = $varName;"));

        c.body = Block.of(block);
      });

  Field _buildEntityField() => Field((m) => m
    ..name = _varEntity
    ..type = refer("Map")
    ..assignment = Code("Map()")
    ..modifier = FieldModifier.var$);

  String _generateTypeParameterizedName(TypeParameterizedElement element) =>
      element.displayName +
      (element.typeParameters.isNotEmpty
          ? '<${element.typeParameters.join(',')}>'
          : '');

  // Iterable<Method> _parseMethods(ClassElement element) =>
  //     element.methods.where((MethodElement m) {
  //       final methodAnnot = _getMethodAnnotation(m);
  //       return methodAnnot != null &&
  //           m.isAbstract &&
  //           (m.returnType.isDartAsyncFuture || m.returnType.isDartAsyncStream);
  //     }).map((m) => _generateMethod(m));
}

extension DartTypeStreamAnnotation on DartType {
  bool get isDartAsyncStream {
    ClassElement element = this.element as ClassElement;
    if (element == null) {
      return false;
    }
    return element.name == "Stream" && element.library.isDartAsync;
  }
}

String _displayString(dynamic e, {bool withNullability = false}) {
  try {
    return e.getDisplayString(withNullability: withNullability);
  } catch (error) {
    if (error is TypeError) {
      return e.getDisplayString();
    } else {
      rethrow;
    }
  }
}

class CollectionPartGenerator extends CollectionGenerator {
  @override
  String _implementClass(ClassElement element, ConstantReader annotation) {
    final className = element.name;
    final fields = element.fields;
    final methods = element.methods;

    final entity = annotation.peek('entity')?.typeValue;

    if (entity == null) {
      throw InvalidGenerationSourceError(
        'Generator cannot create target `$className` because it doesn\'t have target entity.',
        todo:
            'Remove the [Collection] annotation from `$className` or define your entity.',
      );
    }
    // collectionAnnotation = Collection(
    //   entity: entity.runtimeType,
    // );
    ClassElement entityClass = entity.element as ClassElement;
    final annotClassConsts = element.constructors
        .where((c) => !c.isFactory && !c.isDefaultConstructor);
    final classBuilder = Class((c) {
      c
        ..name = '_$className'
        ..types.addAll(element.typeParameters.map((e) => refer(e.name)))
        ..fields.addAll([
          _buildDbField(),
          _buildEntityField(),
          ..._buildFields(
              fields.where((field) => isColumnField(field)).toList())
        ])
        ..methods.addAll(_generateMethods(
            methods
                .where((method) =>
                    isQueryMethod(method) ||
                    isInsertMethod(method) ||
                    isUpdateMethod(method))
                .toList(),
            entityClass))
        ..constructors
            .addAll([_generateDefaultConstructor(element, annotation)]);
      // ..methods.addAll(_parseMethods(element));
      if (annotClassConsts.isEmpty) {
        // c.constructors.add(_generateConstructor(entity));
        c.implements.add(refer(_generateTypeParameterizedName(element)));
      } else {
        c.extend = Reference(_generateTypeParameterizedName(element));
      }
    });

    final emitter = DartEmitter();
    return DartFormatter().format('${classBuilder.accept(emitter)}');
  }

  Field _buildDbField() {
    return Field((f) {
      f
        ..name = "db"
        ..modifier = FieldModifier.var$
        ..type = refer("late SonicDb");
    });
  }

  Constructor _generateDefaultConstructor(
      ClassElement element, ConstantReader annotation) {
    DartObject entity = annotation.peek("entity")!.objectValue;

    var c = Constructor((cc) {
      cc.requiredParameters.add(Parameter((p) {
        p
          ..name = "db"
          ..type = refer("SonicDb")
          ..named = true;
      }));

      final block = <Code>[Code("this.db = db;")];

      var annotation = getAnnotation(entity.toTypeValue()!.element!, Entity);
      var nameConst = annotation!.peek("name")!.stringValue;
      String varName = "entity${entity.toTypeValue()!.element!.name}";
      ClassElement entityClass = entity.toTypeValue()!.element as ClassElement;
      var entityFields =
          entityClass.fields.where((field) => isColumnField(field));

      block.add(Code("var $varName = Map();"));
      block.add(Code("$varName['name'] = ${literal(nameConst)};"));
      // block.add(Code("$varName['indicies'] = "));
      block.add(Code("$varName['fields'] = Map();"));
      entityFields.forEach((field) {
        var typeString = getFieldSqlType(field);
        var varFieldInfo =
            "entity${entity.toTypeValue()!.element!.name}_${field.name}";

        block.add(Code("var $varFieldInfo = Map();"));
        field.metadata.forEach((metadata) {
          var meta = ConstantReader(metadata.computeConstantValue());
          if (meta.instanceOf(typeChecker(PrimaryKey))) {
            var autoGenerated = meta.peek("autoGenerated")?.boolValue ?? false;
            block.add(Code("$varFieldInfo[${literal("primaryKey")}] = true;"));
            block.add(Code(
                "$varFieldInfo[${literal("autoGenerated")}] = $autoGenerated;"));
          } else if (meta.instanceOf(typeChecker(ColumnInfo))) {
            // print(
            //     "meta field is column ${meta.instanceOf(typeChecker(ColumnInfo))}");
            var columnName = meta.peek("name")?.stringValue ?? field.name;
            var type = meta.peek("type")?.stringValue ?? typeString;
            block.add(Code(
                "$varFieldInfo[${literal("name")}] = ${literal(columnName)};"));
            block.add(
                Code("$varFieldInfo[${literal("type")}] = ${literal(type)};"));
          }
        });
        block.add(Code(
            "$varName['fields'][${literal(field.name)}] = $varFieldInfo;"));
      });
      block.add(Code("${CollectionGenerator._varEntity} = $varName;"));
      cc.body = Block.of(block);
    });
    return c;
  }

  Iterable<Method> _generateMethods(
      List<MethodElement> methods, ClassElement entity) {
    // List<Method> results = [];

    return methods.where((MethodElement m) {
      final methodAnnot = _getMethodAnnotation(m);
      // print("Collection : method annotations $methodAnnot");
      return methodAnnot != null && m.isAbstract; //&&
      // (m.returnType.isDartAsyncFuture || m.returnType.isDartAsyncStream);
    }).map((m) => _buildMethod(m, entity));
  }

  Method _buildMethod(MethodElement m, ClassElement entity) {
    print("building method ${m.name}");
    return Method((mm) {
      // print("return types $returnTypes");
      mm
        ..returns =
            refer(_displayString(m.type.returnType, withNullability: true))
        ..name = m.displayName
        ..types.addAll(m.typeParameters.map((e) => refer(e.name)))
        ..modifier =
            m.returnType.isDartAsyncFuture ? MethodModifier.async : null
        ..annotations.add(CodeExpression(Code("override")));

      /// required parameters
      mm.requiredParameters.addAll(m.parameters
          .where((it) => it.isRequiredPositional || it.isRequiredNamed)
          .map((it) => Parameter((p) => p
            ..name = it.name
            ..type = p.type
            ..named = it.isNamed)));

      /// optional positional or named parameters
      mm.optionalParameters.addAll(m.parameters.where((i) => i.isOptional).map(
          (it) => Parameter((p) => p
            ..name = it.name
            ..named = it.isNamed
            ..type = p.type
            ..defaultTo = it.defaultValueCode == null
                ? null
                : Code(it.defaultValueCode!))));

      mm.body = _buildMethodBody(m, entity);
    });
  }

  Code _buildMethodBody(MethodElement m, ClassElement entity) {
    var blocks = <Code>[
      Code("var db = this.db;"),
    ];

    if (isQueryMethod(m)) {
      var query = _getQuery(m);
      final queryArguments =
          query.split(" ").where((str) => str.startsWith(":"));

      queryArguments.forEach((arg) {
        String argName = arg.replaceFirst(":", "");
        String to = arg.replaceFirst(":", "\$");
        var argParams =
            m.parameters.where((element) => element.name == argName);

        if (argParams.length > 0) {
          if (argParams.first.type.isDartCoreString) {
            query = query.replaceAll(arg, '"$to"');
          } else {
            query = query.replaceAll(arg, to);
          }
        }
      });

      blocks.add(Code("await db.open();"));
      blocks.add(Code("var results = await db.query(${literal(query)});"));

      // print("collection method return type ${m.returnType}");
      if (_isFutureMethod(m)) {
        var typeString = _getFutureReturnType(m.returnType);

        if (_isListType(typeString)) {
          var dataType = _getListDataType(typeString);
          blocks.addAll([
            Code("if(results is List) {"),
            Code("  var list = <$dataType>[];"),
            Code("  for(var item in results) {"),
            Code("    var listItem = $dataType(value: item);"),
            Code("    list.add(listItem);"),
            // Code("    for(var key in $_varEntity.keys) {"),
            // Code("      var fieldValue = $_varEntity[key];"),
            // Code("    }"),
            Code("  }"),
            Code("  return list;"),
            Code("}"),
            Code("await db.close();"),
            Code("return [];"),
          ]);
        } else {
          if (isIntegerType(typeString) ||
              isStringType(typeString) ||
              isDoubleType(typeString) ||
              isFloatType(typeString)) {
            blocks.addAll([
              Code("if(results is List) {"),
              Code("  var item = results[0];"),
              Code("  if(item is Map && item.keys.length == 1) {"),
              Code("    return item[item.keys.first];"),
              Code("  } else { "),
              if (isNullableType(typeString)) Code("    return null;"),
              if (!isNullableType(typeString) &&
                  (isIntegerType(typeString) ||
                      isDoubleType(typeString) ||
                      isFloatType(typeString)))
                Code("    return 0;"),
              Code("  }"),
              Code("} else if(results is Map && results.keys.length == 1) {"),
              Code("    return results[results.keys.first];"),
              Code("} else {"),
              Code("  return results as $typeString;"),
              Code("}"),
            ]);
          } else {
            blocks.addAll([
              Code("if(results is List) {"),
              Code("  return $typeString(value: results[0]);"),
              Code("} else if(results is Map) {"),
              Code("  return $typeString(value: results);"),
              Code("} else { "),
              Code(
                  "  throw Exception('cannot convert received data to type $typeString');"),
              Code("}")
            ]);
          }
        }
      }
    } else if (isInsertMethod(m)) {
      var parameter =
          m.parameters.where((element) => element.isRequiredPositional).first;

      blocks.add(
          Code("var tableName = ${CollectionGenerator._varEntity}['name'];"));
      if (_isListType(parameter.type)) {
        blocks.addAll([
          Code(
              "List<Map> data = ${parameter.name}.map((item) => item.toMap()).toList();"),
          Code("await db.open();"),
          Code("await db.insertAll(tableName, data);"),
        ]);
      } else {
        blocks.addAll([
          Code("var data = ${parameter.name}.toMap();"),
          Code("await db.open();"),
          Code("await db.insert(tableName, data);"),
        ]);
      }
      blocks.add(Code("await db.close();"));
    } else if (isUpdateMethod(m)) {
      var parameters = m.parameters;

      if (!_isColumnsValid(parameters, entity)) {
        throw InvalidGenerationSourceError(
          'Generator cannot create method target `${m.name}` some parameters doesn\'t match with entity fields.',
          todo:
              'Remove the [Update] annotation from `${m.name}` or correct your parameters name.',
        );
      }

      blocks.add(
          Code("var tableName = ${CollectionGenerator._varEntity}['name'];"));

      if (isUpdateMethodHasConditions(m) && m.returnType.isDartAsyncFuture) {
        // TODO
        var annotation = getAnnotation(m, Update);

        List<String> conditions = annotation!
            .peek("conditions")!
            .listValue
            .map((e) => e.toStringValue()!)
            .toList();

        // var whereClause = [];
        var varValue = "value";
        var varWhereClause = "whereClause";
        blocks.add(Code("var $varWhereClause = [];"));
        blocks.add(Code("var $varValue = Map();"));
        var valueParameters = _getValueParameters(parameters,
            conditions.map((e) => _getUpdateArg(e)['name'] as String).toList());
        for (var condition in conditions) {
          var arg = _getUpdateArg(condition, fields: entity.fields);
          var columnName = _getUpdateCulumnName(condition);
          print("condition $arg");
          if (isStringType(arg['type'])) {
            var val = literal("$columnName = \"\$${arg['name']}\"");

            blocks.add(Code("$varWhereClause.add($val);"));
          } else {
            var val = literal("$columnName = \$${arg['name']}");
            blocks.add(Code("$varWhereClause.add($val);"));
          }
        }

        for (var parameter in valueParameters) {
          final columnField = entity.fields
              .where((field) => field.name == parameter.name)
              .first;
          var columnAnnot = getAnnotation(columnField, ColumnInfo);
          var columnName = columnAnnot!.peek("name")!.stringValue;
          blocks.add(
              Code("$varValue[${literal(columnName)}] = ${parameter.name};"));
        }

        blocks.addAll([
          Code("await db.open();"),
          Code(
              "var results = await db.update(tableName, $varValue, $varWhereClause.join(${literal(" AND ")}));"),
          Code("await db.close();"),
          Code("return results;"),
        ]);
      } else if (isUpdateMethodReturnOperation(m)) {
        blocks.add(Code(
            "return UpdateOperation(db, tableName, ${CollectionGenerator._varEntity});"));
      }
    }

    return Block.of(blocks);
  }

  List<ParameterElement> _getValueParameters(
      List<ParameterElement> parameters, List<String> args) {
    return parameters.where((element) => !args.contains(element.name)).toList();
  }

  Map _getUpdateArg(String condition, {List<FieldElement>? fields}) {
    var map = Map();
    var name = condition
        .replaceAll(" ", "")
        .split("=")
        .where((element) => element.startsWith(":"))
        .first
        .replaceAll(":", "");

    map['name'] = name;

    if (fields != null) {
      // print("finding parameter $name in ${valueParameters.map((e) => e.name)")
      var field = fields.where((element) => element.name == name);
      if (field.length > 0) map['type'] = _displayString(field.first.type);
    }
    return map;
  }

  String _getUpdateCulumnName(String condition) {
    return condition.replaceAll(" ", "").split("=").first;
  }

  bool _isColumnsValid(List<ParameterElement> parameters, ClassElement entity) {
    var fieldNames = entity.fields.map((e) => e.name);
    return parameters.every((element) => fieldNames.contains(element.name));
  }

  String _getTableName(Element element) {
    ClassElement entityClass = element as ClassElement;
    var annotation = getAnnotation(entityClass, Entity);
    var tableName = annotation!.peek("name")!.stringValue;

    return tableName;
  }
}
