import 'sonicdb.dart';

class BaseOperation<T> {
  final SonicDb db;
  final String table;
  final Map? entity;
  final T? instance;

  List<String> whereClause = [];

  BaseOperation(this.db, this.table, {this.entity, this.instance});

  BaseOperation where(String param1) {
    whereClause.add(param1);
    return this;
  }
}

class UpdateOperation extends BaseOperation {
  UpdateOperation(SonicDb db, String table, Map entity)
      : super(db, table, entity: entity);

  Map _values = Map();
  UpdateOperation set(String column, value) {
    if (entity != null) {
      if (!_validateColumnName(column)) {
        throw Exception("column $column doesn't exists in entity fields.");
      }
      var columnName = _getSqlColumnName(column);
      _values[columnName] = value;
    } else {
      _values[column] = value;
    }
    return this;
  }

  bool _validateColumnName(String name) {
    if (!entity!.containsKey("fields")) {
      return false;
    }

    String? columnName = _getSqlColumnName(name);
    return columnName != null;
  }

  String? _getSqlColumnName(String name) {
    if (!entity!.containsKey("fields")) {
      return null;
    }

    Map fields = entity!["fields"];

    String? realColumnName;

    for (var entry in fields.entries) {
      if (entry.key == name && entry.value.containsKey('name')) {
        realColumnName = entry.value['name'];
        break;
      } else if (entry.value['name'] == name) {
        realColumnName = name;
        break;
      }
    }

    return realColumnName;
  }

  Future exec() async {
    return db.update(table, _values, whereClause.join(" AND "));
  }
}

class SelectOperation<T> extends BaseOperation<T> {
  int _limit = 0;
  bool _distinct = false;
  List<String> _groups = [];
  List<String> _orders = [];
  List<String> _columns = [];

  SelectOperation(SonicDb db, String table, this._columns) : super(db, table);

  SelectOperation distinct(bool distinct) {
    _distinct = distinct;
    return this;
  }

  SelectOperation limit(int limit) {
    _limit = limit;
    return this;
  }

  SelectOperation groupBy(String columnName) {
    _groups.add(columnName);
    return this;
  }

  SelectOperation orderBy(String order) {
    _orders.add(order);
    return this;
  }

  Future<dynamic> exec() async {
    if (table == null || entity == null) {
      throw Exception("table or entity parameter cannot be null");
    }

    // if (instance == null) {
    //   throw Exception("instance of object to assign cannot be null");
    // }
    var query =
        "SELECT ${_distinct ? "DISTINCT" : ""} ${_columns.join(",")} FROM $table";

    if (whereClause.length > 0) {
      query += " WHERE ${whereClause.join(" AND ")}";
    }
    if (_orders.length > 0) {
      query += " ORDER BY ${_orders.join(",")}";
    }
    if (_limit > 0) {
      query += " LIMIT $_limit";
    }
    await db.open();
    var results = await db.query(query);
    await db.close();
    if (results is List && _limit == 1) {
      return results[0];
    }

    return results;
  }
}

class DeleteOperation extends BaseOperation {
  DeleteOperation(SonicDb db, String table) : super(db, table);
  // Future<dynamic> exec() async {
  //   return db.delete(query);
  // }
}

// class ReplaceOperation extends BaseOperation {
//   ReplaceOperation(SonicDb db, String table) : super(db, table);
// }
