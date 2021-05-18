import 'dart:async';

class AsyncTaskQueue {
  final _queuedAsyncTaskController = StreamController<AsyncTaskQueueEntry>();

  AsyncTaskQueue() {
    _process();
  }

  Future<void> _process() async {
    await for (var entry in _queuedAsyncTaskController.stream) {
      try {
        final result = await entry.asyncTask();
        entry.completer.complete(result);
      } catch (e, stacktrace) {
        entry.completer.completeError(e, stacktrace);
      }
    }
  }

  Future<dynamic> schedule(AsyncTask asyncTask) async {
    final completer = Completer<dynamic>();
    _queuedAsyncTaskController.add(AsyncTaskQueueEntry(asyncTask, completer));
    return completer.future;
  }
}

class AsyncTaskQueueEntry {
  final AsyncTask asyncTask;
  final Completer completer;

  AsyncTaskQueueEntry(this.asyncTask, this.completer);
}

typedef AsyncTask = Future<dynamic> Function();
