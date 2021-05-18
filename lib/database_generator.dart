import 'dart:async';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:logging/src/logger.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:code_builder/code_builder.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';
import 'package:dart_style/dart_style.dart';
import 'package:sonicdb/annotation.dart';

import 'utils.dart';
// import 'package:build/src/builder/build_step.dart';
// import 'package:source_gen/source_gen.dart';

// class SonicDbOptions {
//   final bool autoCastResponse;

//   SonicDbOptions({this.autoCastResponse = false});

//   SonicDbOptions.fromOptions([BuilderOptions options])
//       : autoCastResponse =
//             (options?.config['auto_cast_response']?.toString() ?? 'true') ==
//                 'true';
// }

class DatabaseGenerator extends GeneratorForAnnotation<Database> {
  static const String _varName = '_name';
  static const String _varEntities = '_entities';
  static const String _varInstance = '_instance';
  static const String _varUseProtectedStorage = '_useDeviceProtectedStorage';
  static const String _varVersion = '_version';

  static Logger logger = Logger("database-generator");

  // static Database databaseAnnotation;
  static Map<String, String> libraryUris = Map();
  Map<String, ClassElement> _collectionFields = Map();
  // Map<ParameterElement, ConstantReader> _getAnnotations(
  //     MethodElement m, Type type) {
  //   var annot = <ParameterElement, ConstantReader>{};
  //   for (final p in m.parameters) {
  //     final a = _typeChecker(type).firstAnnotationOf(p);
  //     if (a != null) {
  //       annot[p] = ConstantReader(a);
  //     }
  //   }
  //   return annot;
  // }

  @override
  String generateForAnnotatedElement(
      Element element, ConstantReader annotation, BuildStep buildStep) {
    print("building element ${element.name}");
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

    var dbName = annotation.peek('name')?.stringValue ?? 'default.db';
    if (!dbName.endsWith(".db")) dbName = "$dbName.db";
    final List<DartObject> entities =
        annotation.peek('entities')?.listValue ?? [];

    ClassElement entityClass =
        entities[0].toTypeValue()!.element as ClassElement;
    var fields = element.fields;
    var methods = element.methods;
    // logger.log(Level.INFO, "fields ${fields}");
    // logger.log(Level.INFO, "methods ${methods}");
    // logger.log(Level.INFO, "entities ${entityClass.fields}");
    // logger.log(Level.INFO, "entity type ${entityClass.thisType}");

    // ClassElement collectionClass = fields[0].type.element;
    // var collectionSuperclass = collectionClass.supertype;
    // var collectionTypeArgument = collectionSuperclass.typeArguments[0];
    // var collectionTypeString = collectionSuperclass.toString();

    // databaseAnnotation = Database(
    //     name: dbName, entities: entities.map((e) => e.runtimeType).toList());

    final annotClassConsts = element.constructors
        .where((c) => !c.isFactory && !c.isDefaultConstructor);

    var generatedImports = _getGeneratedImports(element);
    var collectionFields =
        fields.where((field) => isCollectionField(field)).toList();
    final classBuilder = Class((c) {
      c
        ..name = '${className}_db'
        ..types.addAll(element.typeParameters.map((e) => refer(e.name)))
        ..fields.addAll([
          _buildNameField(dbName),
          _buildEntitiesField(entities),
          _buildInstanceField(element),
          ..._buildCollectionFields(collectionFields)
        ])
        ..methods.addAll([_generateInstanceGetter(element)])
        ..constructors.addAll(
          annotClassConsts.map(
            (e) => _generateConstructor(dbName, entities, collectionFields,
                superClassConst: e),
          ),
        );
      if (annotClassConsts.isEmpty) {
        c.constructors
            .add(_generateConstructor(dbName, entities, collectionFields));
        c.implements.add(refer(_generateTypeParameterizedName(element)));
      } else {
        // c.constructors.add(_generateConstructor(dbName, entities));
        c.extend = Reference(_generateTypeParameterizedName(element));
      }
    });
    final libraryBuilder = Library((l) {
      for (var lib in element.library.imports) {
        // print("CollectionGenerator : library source ${lib.uri}");
        l.body.add(Code("import '${lib.uri.toString()}';"));
      }

      l.body.add(Code("import '${element.source.uri.toString()}';"));

      l.body.add(generatedImports);
      l.body.add(classBuilder);
    });

    final emitter = DartEmitter();
    return DartFormatter().format('${libraryBuilder.accept(emitter)}');
  }

  Block _getGeneratedImports(ClassElement element) {
    var fields =
        element.fields.where((field) => isCollectionField(field)).toList();
    var methods = element.methods;
    var results = <Code>[];

    for (var field in fields) {
      ClassElement collectionClass = field.type.element as ClassElement;
      var collectionName = collectionClass.name;
      var generatedName = "$collectionName.collection";
      results.add(Code(
          "import '${collectionClass.source.uri.toString().replaceFirst(collectionName, generatedName)}';"));

      _collectionFields[field.name] = collectionClass;
    }

    return Block.of(results);
  }

  // bool isCollectionMethod(MethodElement method) {
  //   ClassElement collectionClass = method.type.element;
  // }
  Field toCollectionField(FieldElement field, ClassElement collectionClass) {
    return Field((m) => m
      ..name = field.name
      ..type = refer("late ${collectionClass.name}")
      // ..assignment = Code("${collectionClass.name}(this)")
      ..modifier = FieldModifier.var$);
  }

  List<Field> _buildCollectionFields(List<FieldElement> fields) {
    List<Field> results = [];

    for (var field in fields) {
      ClassElement collectionClass = field.type.element as ClassElement;
      results.add(toCollectionField(field, collectionClass));
    }

    return results;
  }

  Method _generateInstanceGetter(ClassElement element) {
    return Method((mm) {
      mm
        ..returns = refer(element.displayName)
        ..name = "getInstance"
        ..static = true;

      final block = <Code>[
        Code("if(_instance != null) {"),
        Code("  return _instance;"),
        Code("} else {"),
        Code(
            "  _instance = ${element.displayName}_db($_varName, $_varEntities);"),
        Code("  return _instance;"),
        Code("}"),
      ];

      mm.body = Block.of(block);
    });
  }

  Constructor _generateConstructor(
    String dbName,
    List<DartObject> entities,
    List<FieldElement> collectionFields, {
    ConstructorElement? superClassConst,
  }) =>
      Constructor((c) {
        // c.optionalParameters.add(Parameter((p) => p
        //   ..named = true
        //   ..name = _varName
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
        final block = <Code>[
          // Code("ArgumentError.checkNotNull($_dioVar,'$_dioVar');"),
          // if (dbName != null && dbName.isNotEmpty)
          //   Code("$_varName ??= ${literal(dbName)};"),
        ];

        _collectionFields.forEach((key, value) {
          block.add(Code("$key = ${value.name}_collection(this);"));
        });

        entities.forEach((entity) {
          String varName = "entity${entity.toTypeValue()!.element!.name}";
          ClassElement entityClass =
              entity.toTypeValue()!.element as ClassElement;
          var entityFields =
              entityClass.fields.where((field) => isColumnField(field));

          block.add(Code("var $varName = Map();"));

          entityFields.forEach((field) {
            print("processing field ${field.name}");
            var typeString = getFieldSqlType(field);
            var varFieldInfo =
                "entity${entity.toTypeValue()!.element!.name}_${field.name}";
            block.add(Code("var $varFieldInfo = Map();"));
            field.metadata.forEach((metadata) {
              var meta = ConstantReader(metadata.computeConstantValue());
              if (meta.instanceOf(typeChecker(PrimaryKey))) {
                var autoGenerated =
                    meta.peek("autoGenerated")?.boolValue ?? false;
                block.add(
                    Code("$varFieldInfo[${literal("primaryKey")}] = true;"));
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

            block
                .add(Code("$varName[${literal(field.name)}] = $varFieldInfo;"));
          });

          block.add(
              Code("$_varEntities[${literal(entityClass.name)}] = $varName;"));
        });

        c.body = Block.of(block);
      });

  Field _buildNameField(String name) => Field((m) => m
    ..name = _varName
    ..type = refer("String")
    ..static = true
    ..assignment = Code("${literal(name)}")
    ..modifier = FieldModifier.var$);

  Field _buildEntitiesField(List<DartObject> entities) {
    // var newEntities = entities.map((e) => e.toTypeValue()!.element!.name);

    return Field((m) => m
      ..name = _varEntities
      ..type = refer("Map<String, dynamic>")
      ..static = true
      ..assignment = Code("Map<String, dynamic>()")
      ..modifier = FieldModifier.var$);
  }

  Field _buildVersionField(int? version) {
    if (version == null) {
      version = 1;
    }
    return Field((m) => m
      ..name = _varVersion
      ..type = refer("int")
      ..static = true
      ..assignment = Code("$version")
      ..modifier = FieldModifier.var$);
  }

  Field _buildProtectedStorageField(bool? useProtectedStorage) {
    if (useProtectedStorage == null) {
      useProtectedStorage = false;
    }
    print("useDeviceProtectedStorage $useProtectedStorage");
    return Field((m) => m
      ..name = _varUseProtectedStorage
      ..type = refer("bool")
      ..static = true
      ..assignment = Code("$useProtectedStorage")
      ..modifier = FieldModifier.var$);
  }

  Field _buildInstanceField(ClassElement element) {
    return Field((m) => m
      ..name = _varInstance
      ..type = refer("${_displayString(element.thisType)}?")
      ..static = true
      ..modifier = FieldModifier.var$);
  }

  String _generateTypeParameterizedName(TypeParameterizedElement element) =>
      element.displayName +
      (element.typeParameters.isNotEmpty
          ? '<${element.typeParameters.join(',')}>'
          : '');

  // ConstantReader _getMethodAnnotation(MethodElement method) {
  //   for (final type in _methodsAnnotations) {
  //     final annot = _typeChecker(type)
  //         .firstAnnotationOf(method, throwOnUnresolved: false);
  //     if (annot != null) return ConstantReader(annot);
  //   }
  //   return null;
  // }

  // Iterable<Method> _parseMethods(ClassElement element) =>
  //     element.methods.where((MethodElement m) {
  //       final methodAnnot = _getMethodAnnotation(m);
  //       return methodAnnot != null &&
  //           m.isAbstract &&
  //           (m.returnType.isDartAsyncFuture || m.returnType.isDartAsyncStream);
  //     }).map((m) => _generateMethod(m));

  // ConstantReader _getMethodAnnotation(MethodElement method) {
  //   for (final type in _methodsAnnotations) {
  //     final annot = _typeChecker(type)
  //         .firstAnnotationOf(method, throwOnUnresolved: false);
  //     if (annot != null) return ConstantReader(annot);
  //   }
  //   return null;
  // }

  // ConstantReader _getHeadersAnnotation(MethodElement method) {
  //   final annot = _typeChecker(retrofit.Headers)
  //       .firstAnnotationOf(method, throwOnUnresolved: false);
  //   if (annot != null) return ConstantReader(annot);
  //   return null;
  // }
}

class DatabasePartGenerator extends DatabaseGenerator {
  @override
  String _implementClass(ClassElement element, ConstantReader annotation) {
    final className = element.name;

    var dbName = annotation.peek('name')?.stringValue ?? 'default.db';
    if (!dbName.endsWith(".db")) dbName = "$dbName.db";
    final List<DartObject> entities =
        annotation.peek('entities')?.listValue ?? [];

    // ClassElement entityClass = entities[0].toTypeValue().element;
    var fields = element.fields;
    final version = annotation.peek('version')?.intValue;
    final useDeviceProtectedStorage =
        annotation.peek('useDeviceProtectedStorage')?.boolValue;
    print("useDeviceProtectedStorage $useDeviceProtectedStorage");
    final annotClassConsts = element.constructors
        .where((c) => !c.isFactory && !c.isDefaultConstructor);
    var collectionFields =
        fields.where((field) => isCollectionField(field)).toList();
    final classBuilder = Class((c) {
      c
        ..name = '_$className'
        ..types.addAll(element.typeParameters.map((e) => refer(e.name)))
        ..fields.addAll([
          _buildNameField(dbName),
          _buildEntitiesField(entities),
          _buildVersionField(version),
          _buildProtectedStorageField(useDeviceProtectedStorage),
          _buildInstanceField(element),
          ..._buildCollectionFields(collectionFields)
        ])
        ..methods.addAll([_generateInstanceGetter(element)])
        ..constructors.addAll(
          annotClassConsts.map(
            (e) => _generateDefaultConstructor(
                element, entities, collectionFields,
                superClassConst: e),
          ),
        );
      // ..methods.addAll(_parseMethods(element));
      var isExtendingSonicDb = element.allSupertypes
              .where((element) =>
                  element.getDisplayString(withNullability: false) == "SonicDb")
              .length >
          0;

      if (annotClassConsts.isEmpty) {
        if (isExtendingSonicDb) {
          var sonicDbSuperClass = element.allSupertypes
              .where((element) =>
                  element.getDisplayString(withNullability: false) == "SonicDb")
              .first;

          c.constructors.add(_generateDefaultConstructor(
              element, entities, collectionFields,
              superClassConst: sonicDbSuperClass.constructors.first));
          c.implements.add(refer(_generateTypeParameterizedName(element)));
          c.extend =
              refer(sonicDbSuperClass.getDisplayString(withNullability: false));

          var abstractMethods =
              sonicDbSuperClass.methods.where((element) => element.isAbstract);

          abstractMethods.forEach((abstractMethod) {
            var implementedMethods = element.methods
                .where((element) =>
                    element.displayName == abstractMethod.displayName)
                .map((e) => Method((m) {
                      var source = _getClassMethodBody(element, e);
                      m
                        ..name = e.name
                        ..returns = refer(abstractMethod.returnType
                            .getDisplayString(withNullability: false))
                        ..modifier = abstractMethod.isAsynchronous
                            ? MethodModifier.async
                            : null
                        ..body = Code(source)
                        ..annotations.add(CodeExpression(Code("override")));
                    }))
                .toList();
            if (implementedMethods.length > 0) {
              c.methods.add(implementedMethods.first);
            } else {
              c.methods.add(Method((m) {
                m
                  ..name = abstractMethod.name
                  ..returns = refer(abstractMethod.returnType
                      .getDisplayString(withNullability: false))
                  ..modifier = abstractMethod.isAsynchronous
                      ? MethodModifier.async
                      : null
                  ..annotations.add(CodeExpression(Code("override")))
                  ..body = Code("");
              }));
            }
          });
        } else {
          c.constructors.add(
              _generateDefaultConstructor(element, entities, collectionFields));
          c.implements.add(refer(_generateTypeParameterizedName(element)));
        }
      } else {
        // c.constructors.add(_generateConstructor(dbName, entities));
        c.extend = Reference(_generateTypeParameterizedName(element));
      }
    });

    final emitter = DartEmitter();
    return DartFormatter().format('${classBuilder.accept(emitter)}');
  }

  Constructor _generateDefaultConstructor(
    ClassElement clazz,
    List<DartObject> entities,
    List<FieldElement> collectionFields, {
    ConstructorElement? superClassConst,
  }) =>
      Constructor((c) {
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
                ..name = element.name
                ..defaultTo = classParamterHasAssignment(clazz, element)
                    ? Code(getParameterAssignment(clazz, element))
                    : null));
            } else {
              c.optionalParameters.add(Parameter((p) => p
                ..named = element.isNamed
                ..type = refer(_displayString(element.type))
                ..name = element.name
                ..defaultTo = classParamterHasAssignment(
                        clazz.supertype!.element, element)
                    ? Code(getParameterAssignment(
                        clazz.supertype!.element, element))
                    : null));
            }
          });
          final paramList = constParams
              .map((e) => (e.isNamed ? '${e.name}: ' : '') + '${e.name}');
          c.initializers
              .add(Code('$superConstName(' + paramList.join(',') + ')'));
        }
        final block = <Code>[];

        collectionFields.forEach((field) {
          var collectionName =
              field.type.getDisplayString(withNullability: false);
          block.add(Code("${field.name} = $collectionName(this);"));
        });

        entities.forEach((entity) {
          var annotation =
              getAnnotation(entity.toTypeValue()!.element!, Entity);
          var nameConst = annotation!.peek("name")!.stringValue;
          var indiciesConst = annotation.peek("indicies")?.listValue;

          String varName = "entity${entity.toTypeValue()!.element!.name}";
          ClassElement entityClass =
              entity.toTypeValue()!.element as ClassElement;

          // print("entity metadata ${metaClass.getField("name")}");
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
                var autoGenerated =
                    meta.peek("autoGenerated")?.boolValue ?? false;
                block.add(
                    Code("$varFieldInfo[${literal("primaryKey")}] = true;"));
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

            print(
                "field type ${_displayString(field.type, withNullability: true)}");
            if (!_displayString(field.type, withNullability: true)
                .endsWith("?")) {
              block.add(Code("$varFieldInfo[${literal("notNull")}] = true;"));
            }
            block.add(Code(
                "$varName['fields'][${literal(field.name)}] = $varFieldInfo;"));
          });

          block.add(Code(
              "${DatabaseGenerator._varEntities}[${literal(entityClass.name)}] = $varName;"));
        });

        c.body = Block.of(block);
      });

  @override
  Method _generateInstanceGetter(ClassElement element) {
    return Method((mm) {
      mm
        ..returns = refer(element.displayName)
        ..name = "getInstance"
        ..static = true;

      final block = <Code>[
        Code("if(_instance != null) {"),
        Code("  return _instance!;"),
        Code("} else {"),
        Code(
            "  _instance = _${element.displayName}(name: ${DatabaseGenerator._varName}, entities: ${DatabaseGenerator._varEntities}, version: ${DatabaseGenerator._varVersion},useDeviceProtectedStorage: ${DatabaseGenerator._varUseProtectedStorage});"),
        Code("  return _instance!;"),
        Code("}"),
      ];

      mm.body = Block.of(block);
    });
  }

  String _getClassMethodBody(ClassElement clazz, MethodElement method) {
    var session = method.session;
    ParsedLibraryResult parsedLibResult =
        session!.getParsedLibraryByElement(clazz.library);
    ElementDeclarationResult declaration =
        parsedLibResult.getElementDeclaration(method)!;

    var source = declaration.node
        .toSource()
        .replaceAll("@override ", "")
        .replaceAll(
            RegExp(r"^[a-zA-Z]+\s[a-zA-Z]+\((.*?)\)\s?{", multiLine: true), "");

    var lastIndex = source.lastIndexOf("}");
    source = source.replaceRange(lastIndex, lastIndex + 1, "");
    // print("method source $source");
    return source;
  }
}

extension DartTypeStreamAnnotation on DartType {
  bool get isDartAsyncStream {
    ClassElement? element = this.element as ClassElement?;
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
