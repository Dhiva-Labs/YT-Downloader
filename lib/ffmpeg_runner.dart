import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

/// Runs ffmpeg either via the system binary (desktop) or the bundled
/// ffmpeg-kit plugin (Android/iOS, and desktop fallback where supported).
class FfmpegRunner {
  bool? _available;
  bool _useSystem = false;

  Future<bool> get available async {
    if (_available != null) return _available!;
    if (Platform.isAndroid || Platform.isIOS) {
      // ffmpeg-kit is bundled with the app.
      _useSystem = false;
      return _available = true;
    }
    try {
      final result = await Process.run('ffmpeg', ['-version']);
      if (result.exitCode == 0) {
        _useSystem = true;
        return _available = true;
      }
    } catch (_) {}
    if (Platform.isWindows || Platform.isMacOS) {
      // The plugin also ships binaries for these.
      _useSystem = false;
      return _available = true;
    }
    return _available = false;
  }

  /// Runs ffmpeg with [args]; throws on a non-zero exit.
  Future<void> run(List<String> args) async {
    if (!await available) {
      throw Exception('ffmpeg is not available on this system');
    }
    if (_useSystem) {
      final result = await Process.run('ffmpeg', args);
      if (result.exitCode != 0) {
        throw Exception('ffmpeg failed: ${result.stderr}');
      }
      return;
    }
    final session = await FFmpegKit.executeWithArguments(args);
    final code = await session.getReturnCode();
    if (!ReturnCode.isSuccess(code)) {
      final logs = await session.getAllLogsAsString();
      throw Exception('ffmpeg failed: ${logs ?? 'unknown error'}');
    }
  }
}
