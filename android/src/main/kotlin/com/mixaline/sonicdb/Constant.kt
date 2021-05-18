package com.mixaline.sonicdb

const val SONICDB_CHANNEL = "com.mixaline.sonicdb/database"
const val METHOD_GET_DATABASE_PATH = "getDatabasePath"
const val METHOD_OPEN_DATABASE = "openDatabase"
const val METHOD_CLOSE_DATABASE = "closeDatabase"
const val METHOD_DELETE_DATABASE = "deleteDatabase"
const val METHOD_QUERY = "query"
const val METHOD_INSERT = "insert"
const val METHOD_INSERT_ALL = "insertAll"
const val METHOD_UPDATE = "update"
const val METHOD_DELETE = "delete"
const val METHOD_CREATE_TABLES_IF_NOT_EXISTS = "createTablesIfNotExists"
const val METHOD_CREATE_TABLE_IF_NOT_EXISTS = "createTableIfNotExists"
const val METHOD_CREATE_DATABASE = "createDatabase"
const val METHOD_CREATE_DATABASE_IF_NOT_EXISTS = "createDatabaseIfNotExists"
const val METHOD_ENABLE_DEBUG = "enableDebugMode"

const val PARAM_NO_RESULT = "noResult";
const val PARAM_CONTINUE_OR_ERROR = "continueOnError";

const val PARAM_USE_DEVICE_PROTECTED_STORAGE = "useDeviceProtectedStorage"

const val PARAM_DATABASE_NAME = "database_name"
const val PARAM_ID = "id"
const val PARAM_DATA = "data"
const val PARAM_PATH = "path"
const val PARAM_READ_ONLY = "readOnly"
const val PARAM_SINGLE_INSTANCE = "singleInstance"
const val PARAM_SQL = "sql"
const val PARAM_SQL_ARGUMENTS = "arguments"
const val PARAM_TABLE = "table"
const val PARAM_REPLACE_ON_CONFLICT = "replaceOnConflict"
const val PARAM_WHERE_CLAUSE = "whereClause"

const val SQLITE_ERROR = "sqlite_error"
const val ERROR_OPEN_FAILED = "open_failed"
const val ERROR_DATABASE_CLOSED = "database_closed"

const val TAG = "SonicDb"
