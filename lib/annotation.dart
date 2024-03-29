import 'package:meta/meta.dart';

class CollectionMethodType {
  static const String SELECT = "SELECT";
  static const String QUERY = "QUERY";
  static const String DELETE = "DELETE";
  static const String UPDATE = "UPDATE";
  static const String INSERT = "INSERT";
}

@immutable
class CollectionMethod {
  /// HTTP request method which can be found in [HttpMethod].
  final String method;

  /// A relative or absolute path, or full URL of the endpoint.
  ///
  /// See [RestApi.baseUrl] for details of how this is resolved against a base URL
  /// to create the full endpoint URL.
  final String? query;
  const CollectionMethod(this.method, {this.query});
}

@immutable
class Database {
  const Database(
      {this.name = "sonicdb",
      this.entities = const [],
      this.version = 1,
      this.useDeviceProtectedStorage = false});

  final String name;
  final List<Type> entities;
  final int version;
  final bool useDeviceProtectedStorage;
}

@immutable
class Entity {
  const Entity({this.name, this.indices});
  final String? name;
  final List<dynamic>? indices;
}

@immutable
class ColumnInfo {
  const ColumnInfo({this.name, this.type});

  final String? name;
  final DataType? type;
}

// TODO: need to add more data type but i think the data type that can be transferred through MethodChannel is limited
// maybe should add a basic data type like Float or Double
enum DataType { INTEGER, TEXT, BLOB }

@immutable
class PrimaryKey {
  const PrimaryKey({this.autoGenerated = false});

  final bool autoGenerated;
}

@immutable
class Query extends CollectionMethod {
  const Query(String query) : super(CollectionMethodType.QUERY, query: query);
}

@immutable
class Select extends CollectionMethod {
  const Select(List<String> columns) : super(CollectionMethodType.SELECT);
}

@immutable
class Update extends CollectionMethod {
  final List<String>? conditions;
  const Update({this.conditions}) : super(CollectionMethodType.UPDATE);
}

@immutable
class Insert extends CollectionMethod {
  const Insert() : super(CollectionMethodType.INSERT);
}

class Collection<T> {
  const Collection(this.entity);
  final Type entity;
}
