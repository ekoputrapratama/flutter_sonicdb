package com.mixaline.sonicdb


object SqlErrorInfo {
  @JvmStatic
  fun getMap(operation: Operation): Map<String, Any?>? {
    var map: MutableMap<String, Any?>? = null
    val command = operation.getSqlCommand()
    if(command != null) {
      map = mutableMapOf()
      map[PARAM_SQL] = command.getSql()
      map[PARAM_SQL_ARGUMENTS] = command.getRawSqlArguments()
    }

    return map
  }
}
