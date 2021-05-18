package com.mixaline.sonicdb

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

interface OperationResult {
  fun error(errorCode: String, errorMessage: String?, errorData: Any?)
  fun success(result: Any?)
}

interface Operation : OperationResult {
  fun getMethod(): String
  fun<T> getArgument(key: String): T?
   fun getSqlCommand(): SqlCommand
  fun getNoResult(): Boolean
  fun getContinueOnError(): Boolean
}

abstract class BaseReadOperation : Operation {
   private fun getSql() : String {
     return getArgument<String>(PARAM_SQL)!!
   }

   private fun getSqlArguments() : List<Any>? {
     return getArgument(PARAM_SQL_ARGUMENTS)
   }

   override fun getSqlCommand() : SqlCommand {
     return SqlCommand(getSql(), getSqlArguments())
   }

  override fun getNoResult(): Boolean {
    return getArgument<Boolean>(PARAM_NO_RESULT) == true
  }

  override fun getContinueOnError(): Boolean {
    return (getArgument<Boolean>(PARAM_CONTINUE_OR_ERROR)) == true
  }
  
  protected abstract fun getOperationResult(): OperationResult;
}

abstract class BaseOperation : BaseReadOperation() {
  // override abstract fun getOperationResult(): OperationResult;

  override fun success(result: Any?) {
    getOperationResult().success(result)
  }

  override fun error(errorCode: String, errorMessage: String?, errorData: Any?) {
    getOperationResult().error(errorCode, errorMessage, errorData)
  }
}

class MethodCallOperation(val methodCall: MethodCall, result: MethodChannel.Result) : BaseOperation() {
  val result: Result
  
  class Result(val result: MethodChannel.Result) : OperationResult {

    override fun success(result: Any?) {
      this.result.success(result)
    }
    override fun error(errorCode: String, errorMessage: String?, errorData: Any?){
      this.result.error(errorCode, errorMessage, errorData)
    }
  }

  init {
    this.result = Result(result)
  }

  override fun getMethod() : String {
    return methodCall.method
  }

  override fun<T> getArgument(key: String): T? {
    return methodCall.argument<T>(key)
  }

  override fun getOperationResult() : OperationResult {
    return result
  }
}
