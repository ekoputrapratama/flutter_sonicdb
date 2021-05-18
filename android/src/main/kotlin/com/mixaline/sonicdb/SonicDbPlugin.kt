package com.mixaline.sonicdb

import android.content.Context
import android.os.Handler
import android.os.HandlerThread
import android.os.Process
import android.content.ContentValues
import android.database.sqlite.SQLiteCantOpenDatabaseException
import android.database.SQLException
import android.database.Cursor
import android.os.Looper

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry.Registrar

import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.embedding.engine.plugins.activity.ActivityAware

import java.io.File

import com.mixaline.sonicdb.utils.*

/** GeneratorPlugin */
class SonicDbPlugin : FlutterPlugin, MethodCallHandler {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private var channel: MethodChannel? = null
  private var context: Context? = null
  private var databasePath: String? = null

  companion object {
    var logLevel: Ln.Level = Ln.Level.NONE
    val _singleInstanceByPath = mutableMapOf<String, Int>()
    val openCloseLocker = Object()
    val databaseMapLocker = Object()
    val databaseMap = mutableMapOf<Int, Database>()
    var databaseId = 0

    private var handlerThread: HandlerThread? = null
    private var handler: Handler? = null

    @Suppress("deprecation")
    @JvmStatic
    fun registerWith(registrar: Registrar){
      val sonicdbPlugin = SonicDbPlugin()
      sonicdbPlugin.onAttachedToEngine(registrar.context(), registrar.messenger())
    }

    @JvmStatic
    fun makeOpenResult(id: Int): Map<String, Any> {
      val result = mutableMapOf<String, Any>()
      result[PARAM_ID] = id
      return result
    }
  }

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    Ln.d(TAG, "onAttachedToEngine")
    onAttachedToEngine(binding.applicationContext, binding.binaryMessenger)
  }

  private fun onAttachedToEngine(context: Context, messenger: BinaryMessenger) {
    this.context = context
    channel = MethodChannel(messenger, SONICDB_CHANNEL)
    channel?.setMethodCallHandler(this)
  }
  
  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = null
    channel?.setMethodCallHandler(null)
    channel = null
  }

  fun getDatabase(id: Int): Database? {
    return databaseMap[id]
  }

  fun getDatabaseOrError(call: MethodCall, result: Result): Database? {
    val id = call.argument<Int>(PARAM_ID)
    val db = getDatabase(id!!)

    if(db != null) {
      return db
    } else {
      result.error(SQLITE_ERROR, "${ERROR_DATABASE_CLOSED} $id", null)
      return null
    }
  }

  fun onOpenDatabaseCall(call: MethodCall, result: Result) {
    val path = call.argument<String>(PARAM_PATH)!!
    val readOnly: Boolean = call.argument<Boolean>(PARAM_READ_ONLY) ?: false
    val singleInstance = call.argument<Boolean>(PARAM_SINGLE_INSTANCE) ?: false

    if(singleInstance) {
      synchronized(databaseMapLocker) { 
        val databaseId = _singleInstanceByPath.get(path)
        if(databaseId != null) {
          val db = databaseMap.get(databaseId)
          if(db != null) {
            if(!db.sqliteDatabase.isOpen()) {
              Ln.d(TAG, "database not opened")
            } else {
              Ln.d(TAG, "database already opened")
              result.success(makeOpenResult(databaseId))
              return
            }
          } 
        }
      }
    }

    // Generate new id
    var newDatabaseId: Int;
    synchronized (databaseMapLocker) {
      newDatabaseId = ++databaseId;
    }

    val databaseId = newDatabaseId
    val db = Database(path, databaseId, singleInstance, logLevel)
    val bgResult = BgResult(result)

    synchronized(databaseMapLocker) {
      if(handler == null) {
        handlerThread = HandlerThread("sonicdb", Process.THREAD_PRIORITY_BACKGROUND)
        handlerThread!!.start()
        handler = Handler(handlerThread!!.looper)
      }

      handler!!.post(object : Runnable {
        override fun run() {
          synchronized(openCloseLocker) { 
            val file = File(path)
            val directory = File(file.parent)
            if(!directory.exists()) {
              if(!directory.mkdirs()) {
                if(!directory.exists()) {
                  bgResult.error(SQLITE_ERROR, "$ERROR_OPEN_FAILED $path", null)
                }
              }
            }

            try {
              if(readOnly) {
                db.openReadOnly()
              } else {
                db.open()
              }
            } catch (e: Exception) {
              val operation = MethodCallOperation(call, result)
              handleException(e, operation, db)
              return
            }

            synchronized(databaseMapLocker) { 
              if (singleInstance) {
                _singleInstanceByPath[path] = databaseId
              }
              databaseMap[databaseId] = db
            }

            Ln.d(TAG, "opened $databaseId $path")
          }
          bgResult.success(makeOpenResult(databaseId))
        }
      })
    }
  }

  fun closeDatabase(db: Database) {
    try {
      db.close()
    } catch(e: Exception) {
      Ln.e(TAG, "error while closing database with id ${db.id}", e)
    }

    synchronized(databaseMapLocker) { 
      if(databaseMap.isEmpty() && handler != null) {
        handlerThread?.quit()
        handlerThread = null
        handler = null
      }
    }
  }

  fun onCloseDatabaseCall(call: MethodCall, result: Result) {
    val databaseId = call.argument<Int>(PARAM_ID)
    val db = getDatabaseOrError(call, result)
    if(db == null) {
      return
    }

    Ln.d(TAG, "closing database with id $databaseId")
    val path = db.path

    synchronized(databaseMapLocker) { 
      databaseMap.remove(databaseId)
      if(db.singleInstance) {
        `_singleInstanceByPath`.remove(path)
      }
    }

    val bgResult = BgResult(result)
    handler?.post(Runnable {
      synchronized(openCloseLocker) { 
        closeDatabase(db)
      }

      bgResult.success(true)
    });
  }

  fun onQueryCall(call: MethodCall, result: Result) {
    val db = getDatabaseOrError(call, result)
    if (db == null) {
      return;
    }
    val bgResult = BgResult(result)
    handler?.post(Runnable {
      val operation = MethodCallOperation(call, bgResult)
      query(db, operation)
    })
  }

  private fun query(db: Database, operation: Operation): Boolean {
    val command = operation.getSqlCommand()
    val results = mutableListOf<Map<String, Any?>>()
    var cursor: Cursor? = null
    try {
      cursor = db.getReadableDatabase().rawQuery(command.getSql(), null)

      while(cursor.moveToNext()) {
        results.add(rowToMap(cursor))
      }
      operation.success(results)
      return true
    } catch(e: Exception) {
      handleException(e, operation, db)
      return false
    } finally {
      if(cursor != null) {
        cursor.close()
      }
    }
  }

  private fun onInsertCall(call: MethodCall, result: Result) {
    val data = call.argument<Map<*, *>>(PARAM_DATA)!!
    val table = call.argument<String>(PARAM_TABLE)!!
    var db = getDatabaseOrError(call, result)
    if(db == null) {
      return
    }

    try {
      val inserted = db.insert(table, data)
      result.success(inserted)
    } catch (e: Exception) {
      result.error("InsertException", e.message, null)
    }
  }

  private fun onInsertAllCall(call: MethodCall, result: Result) {
    val data = call.argument<List<Map<*, *>>>(PARAM_DATA)!!
    val replaceOnConflict = call.argument<Boolean>(PARAM_REPLACE_ON_CONFLICT)!!
    val table = call.argument<String>(PARAM_TABLE)!!
    
    var database = getDatabaseOrError(call, result)
    if(database == null) {
      return
    }
    val db = database.getWritableDatabase()
    val results = mutableListOf<Boolean>();
    for(item in data) {
      try {
        val values = toContentValues(item)
        val inserted = db.insert(table, null, values)
        results.add(inserted > 0)
      } catch (e: Exception) {
        results.add(false)
      }
    }
  }

  private fun onCreateTablesIfNotExistsCall(call: MethodCall, result: Result){
    Ln.d(TAG, "onCreateTablesIfNotExistsCall")
    var entities = call.argument<Map<*, *>>("entities")!!
    val useDeviceProtectedStorage = call.argument<Boolean>("useDeviceProtectedStorage")!!
    var db = getDatabaseOrError(call, result)
    if(db == null) {
      return
    }

    //db.open()
    try {
      entities.forEach {
        val name = getEntityName(it.value as Map<*, *>)
        val columns = getEntityColumns(it.value as Map<*, *>)
  
        db.createTableIfNotExists(name, columns)
      }
    } catch(e: Exception) {
      Ln.e(TAG, e.message, e)
      result.error("CreateSqlTable", e.message, null)
    } finally {
      //db.close()
      result.success(true)
    }
  }

  fun onGetDatabasePathCall(call: MethodCall, result: Result) {
    val useDeviceProtectedStorage = call.argument<Boolean>(PARAM_USE_DEVICE_PROTECTED_STORAGE)!!
    var storageContext: Context? = null

    if(useDeviceProtectedStorage && isAtLeastN()) {
      Ln.d("using device protected storage")
      storageContext = context!!.createDeviceProtectedStorageContext()
    } else {
      storageContext = context
    }

    if(databasePath == null) {
      val dummyName = "dummy.db"
      val file = storageContext!!.getDatabasePath(dummyName)
      databasePath = file.parent
    }

    Ln.d("Database path $databasePath")
    result.success(databasePath)
  }

  fun onUpdateCall(call: MethodCall, result: Result) {
    val data = call.argument<Map<*, *>>(PARAM_DATA)!!
    val table = call.argument<String>(PARAM_TABLE)!!
    val whereClause = call.argument<String>(PARAM_WHERE_CLAUSE)
    val db = getDatabaseOrError(call, result)
    if(db == null) {
      return;
    }

    val bgResult = BgResult(result)
    handler?.post(Runnable {
      val operation = MethodCallOperation(call, bgResult)
      update(db, operation, table, toContentValues(data), whereClause)
    });
  }

  fun update(database: Database, operation: Operation, table: String, values: ContentValues, whereClause: String?) {
    
    try {
      val updated = database.update(table, values, whereClause)
      operation.success(updated)
    } catch(e: Exception) {
      handleException(e, operation, database)
    }
  }

  fun onDeleteCall(call: MethodCall, result: Result) {
    
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when(call.method) {
      METHOD_OPEN_DATABASE -> {
        onOpenDatabaseCall(call, result)
      }
      METHOD_CLOSE_DATABASE -> {
        onCloseDatabaseCall(call, result)
      }
      METHOD_QUERY -> {
        onQueryCall(call, result)
      }
      METHOD_GET_DATABASE_PATH -> {
        Ln.d(TAG, "getDatabasePath")
        onGetDatabasePathCall(call, result)
      }
      METHOD_CREATE_TABLES_IF_NOT_EXISTS -> {
        onCreateTablesIfNotExistsCall(call, result)
      }
      METHOD_INSERT -> {
        onInsertCall(call, result)
      }
      METHOD_INSERT_ALL -> {
        onInsertAllCall(call, result)
      }
      METHOD_UPDATE -> {
        onUpdateCall(call, result);
      }
      METHOD_DELETE -> {}
    }
  }

  private fun handleException(e: Exception, operation: Operation, db: Database) {
    if (e is SQLiteCantOpenDatabaseException) {
      operation.error(SQLITE_ERROR, ERROR_OPEN_FAILED + " " + db.path, null);
      return;
    } else if (e is SQLException) {
      operation.error(SQLITE_ERROR, e.message, SqlErrorInfo.getMap(operation));
      return;
    }
    operation.error(SQLITE_ERROR, e.message, SqlErrorInfo.getMap(operation));
  }

  private class BgResult(val result: Result) : Result {
    val handler = Handler(Looper.getMainLooper())
    override fun success(results: Any?) {
      handler?.post(Runnable {
        result.success(results)
      })
    }

    override fun error(errorCode: String, errorMessage: String?, errorData: Any?) {
      handler?.post(Runnable {
        result.error(errorCode, errorMessage, errorData)
      })
    }

    override fun notImplemented() {
      handler?.post(Runnable {
        result.notImplemented()
      })
    }
  }
}
