import 'dart:collection';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/services.dart';

import 'async_task.dart';

// class Document with MapMixin<String, dynamic> implements Map<String, dynamic> {}
final MethodChannel _channel =
    const MethodChannel("com.mixaline.sonicdb/database");

const String PARAM_ID = "id";
const String PARAM_DATA = "data";
const String PARAM_PATH = "path";
const String PARAM_SQL = "sql";
const String PARAM_TABLE = "table";
const String PARAM_ENTITY = "entity";
const String PARAM_ENTITIES = "entities";
const String PARAM_SINGLE_INSTANCE = "singleInstance";
const String PARAM_REPLACE_ON_CONFLICT = "replaceOnConflict";
const String PARAM_WHERE_CLAUSE = "whereClause";
const String PARAM_USE_DEVICE_PROTECTED_STORAGE = "useDeviceProtectedStorage";

abstract class SonicDb {
  final String name;
  final Map<String, dynamic> entities;
  final int version;
  final _asyncTaskQueue = AsyncTaskQueue();

  int _id = 0;
  bool _opened = false;
  bool _initialized = false;
  bool useDeviceProtectedStorage;
  bool get opened => _opened;

  SonicDb(
      {this.name = "sonicdb",
      this.entities = const {},
      this.version = 1,
      this.useDeviceProtectedStorage = false}) {
    log("useDeviceProtectedStorage $useDeviceProtectedStorage");
    // if (useDeviceProtectedStorage != null) {
    //   this.useDeviceProtectedStorage = useDeviceProtectedStorage;
    // }
    init();
  }

  Future init() async {
    return _asyncTaskQueue.schedule(() async {
      if (_initialized) return true;
      log("initializing database");
      if (!opened) await _open(singleInstance: true);
      var args = Map();
      args[PARAM_ID] = _id;
      args[PARAM_ENTITIES] = entities;
      args[PARAM_USE_DEVICE_PROTECTED_STORAGE] = useDeviceProtectedStorage;
      await _channel.invokeMethod("createTablesIfNotExists", args);
      onCreate();
      if (opened) await _close();
      _initialized = true;
    });
  }

  void ensureInitialized() {
    while (!_initialized) {
      sleep(Duration(milliseconds: 200));
    }
  }

  Future open({bool singleInstance = true}) async {
    // if (!_initialized) {
    //   throw Exception("database hasn't been initialized");
    // } else {
    //   return _open(singleInstance: singleInstance);
    // }
    return _asyncTaskQueue.schedule(() async {
      if (!_initialized) {
        throw Exception("database hasn't been initialized");
      } else {
        return _open(singleInstance: singleInstance);
      }
    });
  }

  Future _open({bool singleInstance = false}) async {
    // log("opening database");
    var args = Map();
    var path = await getDatabasePath(useDeviceProtectedStorage);
    args[PARAM_PATH] = "$path/$name";
    args[PARAM_SINGLE_INSTANCE] = singleInstance;
    args[PARAM_USE_DEVICE_PROTECTED_STORAGE] = useDeviceProtectedStorage;
    log("opening database with path ${args['path']}");
    var result = await _channel.invokeMethod("openDatabase", args);
    if (result is int && result > 0) {
      _opened = true;
      _id = result;
    } else if (result is Map) {
      _opened = true;
      _id = result[PARAM_ID];
    }
    return _opened;
  }

  Future close() async {
    // return _close();
    return _asyncTaskQueue.schedule(() => _close());
  }

  Future _close() async {
    var args = Map();
    args[PARAM_ID] = _id;
    log("closing database with id $_id");
    args[PARAM_USE_DEVICE_PROTECTED_STORAGE] = useDeviceProtectedStorage;
    var result = await _channel.invokeMethod("closeDatabase", args);
    if (result is bool && result == true) {
      _opened = false;
    }
    // _id = null;
    return !_opened;
  }

  Future query(String query, {Map? entity}) async {
    if (!_opened) {
      throw Exception("Database is not opened");
    }
    log("query database $_id $query");
    var args = Map();
    args[PARAM_ID] = _id;
    args[PARAM_SQL] = query;
    args[PARAM_USE_DEVICE_PROTECTED_STORAGE] = useDeviceProtectedStorage;

    if (entity != null) {
      args[PARAM_ENTITY] = entity;
    }

    var data = await _channel.invokeMethod("query", args);

    return data;
  }

  Future insert(String table, Map data) async {
    if (!_opened) {
      throw Exception("Database is not opened");
    }
    // log("inserting data $data to database $_id");

    final args = Map();
    args[PARAM_ID] = _id;
    args[PARAM_DATA] = data;
    args[PARAM_TABLE] = table;
    args[PARAM_USE_DEVICE_PROTECTED_STORAGE] = useDeviceProtectedStorage;
    // args[PARAM_ENTITY] = entity;
    var success = await _channel.invokeMethod("insert", args);

    return success;
  }

  Future insertAll(String table, List<Map> data,
      {bool replaceOnConflict = false}) async {
    if (!_opened) {
      throw Exception("Database is not opened");
    }
    log("inserting data $data to database $_id");

    final args = Map();
    args[PARAM_ID] = _id;
    args[PARAM_DATA] = data;
    args[PARAM_TABLE] = table;
    args[PARAM_REPLACE_ON_CONFLICT] = replaceOnConflict;
    args[PARAM_USE_DEVICE_PROTECTED_STORAGE] = useDeviceProtectedStorage;
    var success = await _channel.invokeMethod("insertAll", args);

    return success;
  }

  Future<bool> update(String table, Map value, String whereClause) async {
    var args = Map();
    args[PARAM_ID] = _id;
    args[PARAM_TABLE] = table;
    args[PARAM_WHERE_CLAUSE] = whereClause;
    args[PARAM_DATA] = value;
    args[PARAM_USE_DEVICE_PROTECTED_STORAGE] = useDeviceProtectedStorage;
    var success = await _channel.invokeMethod("update", args);

    return success;
  }

  Future delete(String table, {String? whereClause}) async {}

  void onUpgrade();
  void onCreate();
}

Future<String> getDatabasePath([bool useProtectedStorage = false]) async {
  // log("getting database path");
  var args = Map();
  args[PARAM_USE_DEVICE_PROTECTED_STORAGE] = useProtectedStorage;
  var result = await _channel.invokeMethod("getDatabasePath", args);
  log("useDeviceProtectedStorage $useProtectedStorage");
  log("database path $result");
  return result;
}
