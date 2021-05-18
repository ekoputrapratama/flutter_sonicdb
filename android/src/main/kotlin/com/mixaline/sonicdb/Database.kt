package com.mixaline.sonicdb

import android.content.ContentValues
import android.database.DatabaseErrorHandler
import android.database.sqlite.SQLiteDatabase

import com.mixaline.sonicdb.utils.*


import java.io.File

class Database(val path: String, val id: Int, val singleInstance: Boolean, val logLevel: Ln.Level) {
  lateinit var sqliteDatabase: SQLiteDatabase
  // lateinit var CONTENT_URI: UR

  fun open() {
    sqliteDatabase = SQLiteDatabase.openDatabase(path, null,
      SQLiteDatabase.CREATE_IF_NECESSARY)
  }

  fun openReadOnly() {
    sqliteDatabase = SQLiteDatabase.openDatabase(path, null,
      SQLiteDatabase.OPEN_READONLY, DatabaseErrorHandler {

    })
  }

  fun close() {
    sqliteDatabase.close()
  }

  fun getWritableDatabase(): SQLiteDatabase {
    return sqliteDatabase
  }

  fun getReadableDatabase(): SQLiteDatabase {
    return sqliteDatabase
  }

  fun getDatabasePath(): String {
    return path
  }

  fun exists(): Boolean {
    return File(path).exists()
  }

  fun createTableIfNotExists(name: String, columns: List<String>) {
    Ln.d(TAG, "create table $name with columns (${columns.joinToString(",")})")
    val db = getReadableDatabase()
    var query = "create table if not exists $name (${columns.joinToString(",")});"
    
    db.execSQL(query)
  }

  fun insert(table: String, value: Map<*, *>): Boolean {
    val db = getWritableDatabase()
    
    val values = toContentValues(value)
    val inserted = db.insert(table, null, values)
    return inserted > 0
  }

  fun update(table: String, values: ContentValues, whereClause: String?): Boolean {
    var updated = false;
    try {
      val db = getWritableDatabase()
      updated = db.update(table, values, whereClause, null) > 0
    } catch(e: Exception) {
      return false
    }
    return updated
  }
  
  fun getData(tableName: String, selection: List<String>) {
    
  }
  
  fun getDataWithRawQuery(query: String) {
    val db = getReadableDatabase()
    val c = db.rawQuery(query, null)
    val results = mutableListOf<Map<String, Any?>>()
    if (c.moveToFirst()) {
      while (!c.isAfterLast) {
        val document = mutableMapOf<String, Any?>()
        for ((index, name) in c.columnNames.withIndex()) {
          val value = parseDataValue(c, index)
          document[name] = value
        }
        results.add(document)
        c.moveToNext()
      }
    }
    db.close()
  }

  fun drop(table: String? = null) {
    if(table == null) {
      val db = sqliteDatabase
      db.execSQL("DROP TABLE IF EXISTS $table")
      db.close()
    } else {
      val db = sqliteDatabase
      val c = db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'", null)

      if(c.moveToFirst()) {
        while(!c.isAfterLast) {
          val name = c.getString(0)
          if (!name.contains("sqlite_sequence") && !name.contains("android_metadata")) {
            Ln.d(TAG, "dropping table $name");
            drop(name);
          }
          c.moveToNext();
        }
      }
      db.close()
      // drop table
      // sqliteDatabase.delete(p0, p1, p2)
    }
  }

  fun isEmpty(): Boolean {
    val db = sqliteDatabase
    val c = db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'", null)
    val tables = mutableListOf<String>()

    if (c.moveToFirst()) {
      while (!c.isAfterLast()) {
        val name = c.getString(0);
        if (!name.contains("sqlite_sequence") && !name.contains("android_metadata")) {
          tables.add(name);
        }
        c.moveToNext();
      }
    }
    db.close();
    return tables.size == 0;
  }

  companion object {
    @JvmStatic
    fun delete(path: String) {
      SQLiteDatabase.deleteDatabase(File(path))
    }
  }
}
