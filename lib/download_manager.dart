import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'yt_service.dart';

enum TaskStatus { running, done, error, cancelled }

class DownloadTask {
  DownloadTask(this.video, this.option);

  final Video video;
  final DownloadOption option;

  double progress = 0;
  String phase = 'Starting…';
  TaskStatus status = TaskStatus.running;
  String? path;
  String? error;
  bool _cancelRequested = false;

  bool get isFinished => status != TaskStatus.running;

  void cancel() => _cancelRequested = true;
}

/// Runs downloads concurrently and notifies the UI as they progress.
class DownloadManager extends ChangeNotifier {
  DownloadManager(this._service);

  final YtService _service;
  final List<DownloadTask> tasks = [];

  bool get hasRunning => tasks.any((t) => t.status == TaskStatus.running);

  DownloadTask start(
    Video video,
    DownloadOption option, {
    void Function(DownloadTask task)? onDone,
  }) {
    final task = DownloadTask(video, option);
    tasks.insert(0, task);
    notifyListeners();

    _service
        .download(
      video,
      option,
      onProgress: (p) {
        task.progress = p.clamp(0, 1);
        notifyListeners();
      },
      onPhase: (phase) {
        task.phase = phase;
        notifyListeners();
      },
      isCancelled: () => task._cancelRequested,
    )
        .then((path) {
      task.status = TaskStatus.done;
      task.path = path;
      task.progress = 1;
      notifyListeners();
      onDone?.call(task);
    }).catchError((Object e) {
      if (e is DownloadCancelled || task._cancelRequested) {
        task.status = TaskStatus.cancelled;
      } else {
        task.status = TaskStatus.error;
        task.error = '$e';
      }
      notifyListeners();
    });

    return task;
  }

  void clearFinished() {
    tasks.removeWhere((t) => t.isFinished);
    notifyListeners();
  }
}
