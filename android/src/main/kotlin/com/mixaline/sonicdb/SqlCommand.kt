package com.mixaline.sonicdb

import android.R.attr
import java.util.*


class SqlCommand(private val sql: String, var rawArguments: List<Any>? = emptyList()) {

  fun getSql():String {
    return sql
  }
  
  fun toValue(value: Any? = null): Any? {
    if(value == null) {
      return null
    } else {
      Ln.d(TAG, "arg ${value::class.java.canonicalName} ${toString()}")

      if(value is List<*>) {
        val list: List<Int> = value as List<Int>
        val blob = ByteArray(list.size)
        for(i in 0..list.size) {
          blob[i] = list[i].toByte()
        }
        return blob
      }
      return value
    }
  }

  fun sanitizeForQuery(): SqlCommand {
    if(rawArguments?.size == 0) {
      return this
    }

    val builder = StringBuilder()
    val sanitizeArguments = mutableListOf<Any>()

    for(i in 0..sql.length) {
      val char = sql[i]
      if(char == '?') {

      }
    }

    return SqlCommand(builder.toString(), sanitizeArguments)
  }

  fun toString(value: Any? = null): String? {
    if(value == null) {
      return null
    } else if(value is ByteArray) {
      val list = mutableListOf<Int>()
      for(byte in value) {
        list.add(byte.toInt())
      }
      return list.toString()
    } else if(value is Map<*, *>) {
      val mapValue = attr.value as Map<Any, Any>
      return fixMap(mapValue).toString()
    } else {
      return value.toString()
    }
  }

  private fun fixMap(map: Map<Any, Any>): Map<String?, Any?> {
    val newMap: MutableMap<String?, Any?> = HashMap()
    for (entry in map.entries) {
      var value: Any? = entry.value
      value = if (value is Map<*, *>) {
        val mapValue = value as Map<Any, Any>
        fixMap(mapValue)
      } else {
        toString(value)
      }
      newMap[toString(entry.key)] = value
    }
    return newMap
  }

  // Query only accept string arguments
  // so should not have byte[]
  private fun getQuerySqlArguments(rawArguments: List<Any>?): Array<String?>? {
    return getStringQuerySqlArguments(rawArguments).toTypedArray()
  }

  private fun getSqlArguments(rawArguments: List<Any>?): Array<Any?>? {
    val fixedArguments: MutableList<Any?> = ArrayList()
    if (rawArguments != null) {
      for (rawArgument in rawArguments) {
        fixedArguments.add(toValue(rawArgument))
      }
    }
    return fixedArguments.toTypedArray()
  }


  // Query only accept string arguments
  private fun getStringQuerySqlArguments(rawArguments: List<Any>?): List<String?> {
    val stringArguments: MutableList<String?> = ArrayList()
    if (rawArguments != null) {
      for (rawArgument in rawArguments) {
        stringArguments.add(toString(rawArgument))
      }
    }
    return stringArguments
  }

  override fun toString(): String {
    return sql + if (rawArguments == null || rawArguments!!.isEmpty()) "" else " " + getStringQuerySqlArguments(rawArguments)
  }

  // As expected by execSQL
  fun getSqlArguments(): Array<Any?>? {
    return getSqlArguments(rawArguments)
  }

  fun getQuerySqlArguments(): Array<String?>? {
    return getQuerySqlArguments(rawArguments)
  }

  fun getRawSqlArguments(): List<Any?>? {
    return rawArguments
  }

  override fun hashCode(): Int {
    return sql?.hashCode() ?: 0
  }

  override fun equals(obj: Any?): Boolean {
    if (obj is SqlCommand) {
      val o = obj
      if (sql != null) {
        if (sql != o.sql) {
          return false
        }
      } else {
        if (o.sql != null) {
          return false
        }
      }
      if (rawArguments!!.size != o.rawArguments!!.size) {
        return false
      }
      for (i in rawArguments!!.indices) {
        // special blob handling
        if (rawArguments!![i] is ByteArray && o.rawArguments!![i] is ByteArray) {
          if (!Arrays.equals(rawArguments!![i] as ByteArray, o.rawArguments!![i] as ByteArray)) {
            return false
          }
        } else {
          if (rawArguments!![i] != o.rawArguments!![i]) {
            return false
          }
        }
      }
      return true
    }
    return false
  }
}
