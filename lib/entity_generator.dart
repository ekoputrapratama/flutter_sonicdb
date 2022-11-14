import 'dart:async';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:code_builder/code_builder.dart';
import 'package:build/build.dart';
import 'package:sonicdb/utils.dart';
import 'package:source_gen/source_gen.dart';
import 'package:dart_style/dart_style.dart';
import 'package:sonicdb/annotation.dart';

// import 'package:build/src/builder/build_step.dart';
// import 'package:source_gen/source_gen.dart';

// class SonicDbOptions {
//   final bool autoCastResponse;

//   SonicDbOptions({this.autoCastResponse});

//   SonicDbOptions.fromOptions([BuilderOptions options])
//       : autoCastResponse =
//             (options?.config['auto_cast_response']?.toString() ?? 'true') ==
//                 'true';
// }
//
extension FieldModifiers on FieldModifier {}

class EntityGenerator extends GeneratorForAnnotation<Entity> {
  static const String _name = 'tableName';

  // Entity entityAnnotation;

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
    // print("building element ${element.name}");
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

    final dbName = annotation.peek('name')?.stringValue ?? 'default.db';
    final entities = annotation.peek('entities')?.listValue ?? [];

    final fields = element.fields;

    // entityAnnotation = Entity(
    //   name: dbName,
    // );

    final annotClassConsts = element.constructors
        .where((c) => !c.isFactory && !c.isDefaultConstructor);
    final classBuilder = Class((c) {
      c
        ..name = '${className}_entity'
        ..types.addAll(element.typeParameters.map((e) => refer(e.name)))
        ..fields.addAll([
          _buildNameField(dbName),
          ..._buildFields(
              element, fields.where((field) => isColumnField(field)).toList())
        ])
        ..methods.addAll([_generateFromMapMethod(element)])
        ..constructors.addAll(
          annotClassConsts.map(
            (e) => _generateConstructor(dbName, superClassConst: e),
          ),
        );
      // ..methods.addAll(_parseMethods(element));
      if (annotClassConsts.isEmpty) {
        c.constructors.add(_generateConstructor(dbName));
        c.implements.add(refer(_generateTypeParameterizedName(element)));
      } else {
        c.extend = Reference(_generateTypeParameterizedName(element));
      }
    });

    final libraryBuilder = Library((b) {
      b.body.add(Code("import '${element.source.uri.toString()}';"));
      for (var lib in element.library.imports) {
        b.body.add(Code("import '${lib.uri.toString()}';"));
      }

      b.body.add(classBuilder);
    });

    final emitter = DartEmitter();
    return DartFormatter().format('${libraryBuilder.accept(emitter)}');
  }

  List<Field> _buildFields(ClassElement clazz, List<FieldElement> fields) {
    List<Field> results = [];

    for (var field in fields) {
      field.isLate;
      results.add(Field((m) => m
        ..name = field.name
        ..assignment = classFieldHasAssignment(clazz, field)
            ? Code(getClassFieldValue(clazz, field))
            : null
        ..type = classFieldHasAssignment(clazz, field)
            ? refer(field.type.getDisplayString(withNullability: true))
            : refer(
                "late ${field.type.getDisplayString(withNullability: true)}")
        ..modifier = FieldModifier.var$));
    }

    return results;
  }

  Constructor _generateConstructor(
    String dbName, {
    ConstructorElement? superClassConst,
  }) =>
      Constructor((c) {
        c.optionalParameters.add(Parameter((p) => p
          ..named = true
          ..name = _name
          ..toThis = true));
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
        final block = [
          // Code("ArgumentError.checkNotNull($_dioVar,'$_dioVar');"),
          if (dbName != null && dbName.isNotEmpty)
            Code("$_name ??= ${literal(dbName)};"),
        ];

        c.body = Block.of(block);
      });

  Field _buildNameField(String name) => Field((m) => m
    ..name = _name
    ..type = refer("String")
    ..modifier = FieldModifier.var$);

  String _generateTypeParameterizedName(TypeParameterizedElement element) =>
      element.displayName +
      (element.typeParameters.isNotEmpty
          ? '<${element.typeParameters.join(',')}>'
          : '');

  Method _generateFromMapMethod(ClassElement element) {
    return Method((mm) {
      mm
        ..returns = refer(element.displayName)
        ..name = "fromMap"
        ..static = true;

      mm.requiredParameters.add(Parameter((p) => p
        ..name = "map"
        ..type = refer("Map<dynamic, dynamic>")
        ..named = true));
      var block = <Code>[];
      var fields = element.fields;
      block.add(Code("var instance = ${element.displayName}_entity();"));
      fields.forEach((field) {
        block.add(
          Code("instance.${field.name} = map[${literal(field.name)}];"),
        );
      });
      block.add(Code("return instance;"));
      mm.body = Block.of(block);
    });
  }
}

class EntityPartGenerator extends EntityGenerator {
  @override
  String generateForAnnotatedElement(
      Element element, ConstantReader annotation, BuildStep buildStep) {
    // print("building element ${element.name}");
    if (element is! ClassElement) {
      final name = element.displayName;
      throw InvalidGenerationSourceError(
        'Generator cannot target `$name`.',
        todo: 'Remove the [RestApi] annotation from `$name`.',
      );
    }
    return _implementClass(element, annotation);
  }

  @override
  String _implementClass(ClassElement element, ConstantReader annotation) {
    final className = element.name;

    final fields = element.fields;

    final annotClassConsts = element.constructors
        .where((c) => !c.isFactory && !c.isDefaultConstructor);

    final classBuilder = Class((c) {
      c
        ..name = '_$className'
        ..types.addAll(element.typeParameters.map((e) => refer(e.name)))
        ..fields.addAll([..._buildFields(element, fields)])
        ..methods.addAll([_generateToMapMethod(element)])
        ..constructors.addAll([_generateDefaultConstructor(element)]);
      // ..methods.addAll(_parseMethods(element));
      if (annotClassConsts.isEmpty) {
        // c.constructors.add(_generateConstructor(dbName));
        c.implements.add(refer(_generateTypeParameterizedName(element)));
      } else {
        c.extend = Reference(_generateTypeParameterizedName(element));
      }
    });

    var emitter = DartEmitter();
    return DartFormatter().format('${classBuilder.accept(emitter)}');
  }

  Constructor _generateDefaultConstructor(ClassElement clazz) {
    var c = Constructor((cc) {
      cc.optionalParameters.add(Parameter((p) {
        p
          ..name = "value"
          ..type = refer("Map?")
          ..named = true;
      }));
      final block = <Code>[Code("if(value != null) {")];

      var fields = clazz.fields.where((element) => isColumnField(element));
      fields.forEach((field) {
        // print(
        //     "field ${field.name} computed value ${getClassFieldValue(clazz, field)}");
        final annotation = getAnnotation(field, ColumnInfo);
        final name = annotation!.peek("name")?.stringValue;
        block.add(Code("this.${field.name} = value[${literal(name)}];"));
      });
      block.addAll([Code("}")]);

      cc.body = Block.of(block);
    });
    return c;
  }

  Method _generateToMapMethod(ClassElement clazz) {
    final fields = clazz.fields.where((element) => isColumnField(element));
    MethodElement? method;
    try {
      method = clazz.methods.firstWhere((element) => element.name == "toMap");
    } catch (e) {
      throw InvalidGenerationSourceError(
        'Generator cannot create target class `${clazz.name}` because it doesn\'t have toMap abstract method.',
        todo:
            'Remove the [Entity] annotation from class `${clazz.name}` or add toMap abstract method so it can be generated.',
      );
    }

    return Method((m) {
      m
        ..returns = refer("Map")
        ..name = "toMap"
        ..annotations.add(CodeExpression(Code("override")));

      m.optionalParameters.add(Parameter((p) {
        p
          ..name = "withPrimaryKey"
          ..type = refer("bool")
          ..defaultTo = Code("false")
          ..named = true;
      }));
      final block = <Code>[];
      if (method != null && !method.isAbstract) {
        var code = getClassMethodBody(clazz, method);
        block.add(Code(code));
      } else {
        // m.annotations.add(CodeExpression(Code("override")));
        block.add(Code("var data = Map();"));
        fields.forEach((field) {
          final annotation = getAnnotation(field, ColumnInfo);
          final name = annotation!.peek("name")?.stringValue;

          if (isAutoGeneratedPrimaryKeyField(field)) {
            block.addAll([
              Code("if(withPrimaryKey) {"),
              Code("  data[${literal(name)}] = this.${field.name};"),
              Code("}")
            ]);
          } else {
            block.add(Code("data[${literal(name)}] = this.${field.name};"));
          }
        });
        block.add(Code("return data;"));
      }

      m.body = Block.of(block);
    });
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

String _displayString(dynamic e) {
  try {
    return e.getDisplayString(withNullability: false);
  } catch (error) {
    if (error is TypeError) {
      return e.getDisplayString();
    } else {
      rethrow;
    }
  }
}
