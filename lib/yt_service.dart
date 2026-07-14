import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'ffmpeg_runner.dart';

class DownloadCancelled implements Exception {
  @override
  String toString() => 'Download cancelled';
}

/// One downloadable choice shown to the user.
class DownloadOption {
  const DownloadOption({
    required this.label,
    required this.container,
    required this.sizeBytes,
    required this.isAudio,
    required this.streamInfo,
    this.mergeAudioInfo,
    this.mp3Bitrate,
    this.blankVideo = false,
  });

  final String label;
  final String container;
  final int sizeBytes;
  final bool isAudio;
  final StreamInfo streamInfo;

  /// When set, [streamInfo] is video-only and this audio stream gets
  /// merged in with ffmpeg after both finish downloading.
  final AudioOnlyStreamInfo? mergeAudioInfo;

  /// When set the downloaded audio gets re-encoded to MP3 at this bitrate.
  final int? mp3Bitrate;

  /// When true [streamInfo] is audio-only and ffmpeg renders it into an MP4
  /// with a black video track — "audio as video".
  final bool blankVideo;

  bool get needsFfmpeg =>
      mergeAudioInfo != null || mp3Bitrate != null || blankVideo;

  String get extension {
    if (mp3Bitrate != null) return 'mp3';
    if (blankVideo) return 'mp4';
    return container == 'mp4' && isAudio ? 'm4a' : container;
  }

  String get sizeText {
    final mb = sizeBytes / (1024 * 1024);
    return mb >= 1024
        ? '${(mb / 1024).toStringAsFixed(2)} GB'
        : '${mb.toStringAsFixed(1)} MB';
  }
}

class FetchResult {
  const FetchResult(this.video, this.videoOptions, this.audioOptions);

  final Video video;
  final List<DownloadOption> videoOptions;
  final List<DownloadOption> audioOptions;
}

class YtService {
  final YoutubeExplode _yt = YoutubeExplode();
  final FfmpegRunner _ffmpeg = FfmpegRunner();

  Future<bool> get ffmpegAvailable => _ffmpeg.available;

  /// Rewrites Shorts/live share links (which often carry `?si=` tracking
  /// params the upstream parser chokes on) into plain watch URLs.
  static String normalizeUrl(String url) {
    final match = RegExp(r'youtube\.[^/\s]+/(?:shorts|live)/([A-Za-z0-9_-]{6,})')
        .firstMatch(url);
    if (match != null) {
      return 'https://www.youtube.com/watch?v=${match.group(1)}';
    }
    return url;
  }

  Future<FetchResult> fetchInfo(String url) async {
    final video = await _yt.videos.get(normalizeUrl(url));
    final manifest =
        await _yt.videos.streamsClient.getManifest(video.id, ytClients: [
      YoutubeApiClient.androidVr,
      YoutubeApiClient.ios,
    ]);
    final hasFfmpeg = await _ffmpeg.available;

    final videoOptions = <DownloadOption>[];
    final audioOptions = <DownloadOption>[];

    // Muxed streams already contain audio — playable everywhere, no ffmpeg.
    final seenMuxed = <String>{};
    for (final s in manifest.muxed.sortByVideoQuality()) {
      final key = '${s.qualityLabel}-${s.container.name}';
      if (!seenMuxed.add(key)) continue;
      videoOptions.add(DownloadOption(
        label: '${s.qualityLabel} • ${s.container.name.toUpperCase()}',
        container: s.container.name,
        sizeBytes: s.size.totalBytes,
        isAudio: false,
        streamInfo: s,
      ));
    }

    // Higher-quality video-only streams, merged with the best audio track.
    if (hasFfmpeg && manifest.audioOnly.isNotEmpty) {
      final bestAudio = manifest.audioOnly.withHighestBitrate();
      final muxedLabels = videoOptions.map((o) => o.label).toSet();
      final seenVideoOnly = <String>{};
      for (final s in manifest.videoOnly.sortByVideoQuality()) {
        if (s.container.name != 'mp4') continue;
        if (!seenVideoOnly.add(s.qualityLabel)) continue;
        final label = '${s.qualityLabel} • MP4';
        if (muxedLabels.contains(label)) continue;
        videoOptions.add(DownloadOption(
          label: label,
          container: 'mp4',
          sizeBytes: s.size.totalBytes + bestAudio.size.totalBytes,
          isAudio: false,
          streamInfo: s,
          mergeAudioInfo: bestAudio,
        ));
      }
      videoOptions.sort((a, b) {
        int q(DownloadOption o) =>
            int.tryParse(o.label.split('p').first) ?? 0;
        return q(b).compareTo(q(a));
      });
    }

    // Audio rendered as an MP4 with a black screen — lets audio-only
    // content (or any link) be saved as a video file.
    if (hasFfmpeg && manifest.audioOnly.isNotEmpty) {
      final bestAudio = _bestAudioForMp4(manifest);
      final kbps = (bestAudio.bitrate.bitsPerSecond / 1000).round();
      videoOptions.add(DownloadOption(
        label: 'Blank screen + audio ($kbps kbps) • MP4',
        container: 'mp4',
        sizeBytes: bestAudio.size.totalBytes,
        isAudio: false,
        streamInfo: bestAudio,
        blankVideo: true,
      ));
    }

    if (hasFfmpeg && manifest.audioOnly.isNotEmpty) {
      final bestAudio = manifest.audioOnly.withHighestBitrate();
      final sourceKbps = (bestAudio.bitrate.bitsPerSecond / 1000).round();
      for (final kbps in [320, 192, 128]) {
        audioOptions.add(DownloadOption(
          label: 'MP3 • $kbps kbps'
              '${kbps > sourceKbps ? ' (source $sourceKbps kbps)' : ''}',
          container: bestAudio.container.name,
          sizeBytes: bestAudio.size.totalBytes,
          isAudio: true,
          streamInfo: bestAudio,
          mp3Bitrate: kbps,
        ));
      }
    }

    final seenAudio = <String>{};
    for (final s in manifest.audioOnly.toList()
      ..sort((a, b) => b.bitrate.compareTo(a.bitrate))) {
      final kbps = (s.bitrate.bitsPerSecond / 1000).round();
      final ext = s.container.name == 'mp4' ? 'M4A' : 'WEBM (Opus)';
      final key = '$kbps-$ext';
      if (!seenAudio.add(key)) continue;
      audioOptions.add(DownloadOption(
        label: '$kbps kbps • $ext',
        container: s.container.name,
        sizeBytes: s.size.totalBytes,
        isAudio: true,
        streamInfo: s,
      ));
    }

    return FetchResult(video, videoOptions, audioOptions);
  }

  /// Downloads [option] for [video]. Reports progress 0..1 and a phase
  /// description through the callbacks; [isCancelled] is polled between
  /// chunks and aborts with [DownloadCancelled]. Returns the saved path.
  Future<String> download(
    Video video,
    DownloadOption option, {
    required void Function(double progress) onProgress,
    required void Function(String phase) onPhase,
    bool Function()? isCancelled,
  }) async {
    final dir = await _downloadsDir();
    final base = _sanitize(video.title);
    final outPath = _uniquePath(dir.path, base, option.extension);

    if (option.mergeAudioInfo != null) {
      onPhase('Downloading video…');
      final vTmp = '$outPath.video.tmp';
      final aTmp = '$outPath.audio.tmp';
      try {
        await _saveStream(option.streamInfo, vTmp,
            (p) => onProgress(p * 0.6), isCancelled);
        onPhase('Downloading audio…');
        await _saveStream(option.mergeAudioInfo!, aTmp,
            (p) => onProgress(0.6 + p * 0.25), isCancelled);
        onPhase('Merging…');
        await _ffmpeg.run([
          '-y',
          '-i', vTmp,
          '-i', aTmp,
          '-c', 'copy',
          outPath,
        ]);
        onProgress(1);
      } finally {
        for (final t in [vTmp, aTmp]) {
          final f = File(t);
          if (f.existsSync()) f.deleteSync();
        }
      }
      return outPath;
    }

    if (option.blankVideo) {
      onPhase('Downloading audio…');
      final tmp = '$outPath.src.tmp.${option.container}';
      try {
        await _saveStream(
            option.streamInfo, tmp, (p) => onProgress(p * 0.7), isCancelled);
        onPhase('Rendering blank-screen video…');
        // AAC in an mp4 container can be copied; anything else re-encodes.
        final audioCodec = option.container == 'mp4'
            ? ['-c:a', 'copy']
            : ['-c:a', 'aac', '-b:a', '192k'];
        await _ffmpeg.run([
          '-y',
          '-f', 'lavfi',
          '-i', 'color=c=black:s=1280x720:r=2',
          '-i', tmp,
          '-shortest',
          '-c:v', 'libx264',
          '-preset', 'veryfast',
          '-tune', 'stillimage',
          '-pix_fmt', 'yuv420p',
          ...audioCodec,
          outPath,
        ]);
        onProgress(1);
      } finally {
        final f = File(tmp);
        if (f.existsSync()) f.deleteSync();
      }
      return outPath;
    }

    if (option.mp3Bitrate != null) {
      onPhase('Downloading audio…');
      final tmp = '$outPath.src.tmp.${option.container}';
      try {
        await _saveStream(
            option.streamInfo, tmp, (p) => onProgress(p * 0.8), isCancelled);
        onPhase('Converting to MP3…');
        await _ffmpeg.run([
          '-y',
          '-i', tmp,
          '-vn',
          '-c:a', 'libmp3lame',
          '-b:a', '${option.mp3Bitrate}k',
          outPath,
        ]);
        onProgress(1);
      } finally {
        final f = File(tmp);
        if (f.existsSync()) f.deleteSync();
      }
      return outPath;
    }

    onPhase(option.isAudio ? 'Downloading audio…' : 'Downloading video…');
    await _saveStream(option.streamInfo, outPath, onProgress, isCancelled);
    return outPath;
  }

  /// Highest-bitrate audio stream, preferring mp4/AAC so it can be copied
  /// into an MP4 container without re-encoding.
  AudioOnlyStreamInfo _bestAudioForMp4(StreamManifest manifest) {
    final mp4Audio = manifest.audioOnly
        .where((s) => s.container.name == 'mp4')
        .toList()
      ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
    return mp4Audio.isNotEmpty
        ? mp4Audio.first
        : manifest.audioOnly.withHighestBitrate();
  }

  Future<void> _saveStream(
    StreamInfo info,
    String path,
    void Function(double) onProgress,
    bool Function()? isCancelled,
  ) async {
    final file = File(path);
    final sink = file.openWrite();
    final total = info.size.totalBytes;
    var received = 0;
    try {
      await for (final chunk in _yt.videos.streamsClient.get(info)) {
        if (isCancelled?.call() ?? false) throw DownloadCancelled();
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress(received / total);
      }
      await sink.flush();
    } catch (_) {
      await sink.close();
      if (file.existsSync()) file.deleteSync();
      rethrow;
    }
    await sink.close();
  }

  Future<Directory> _downloadsDir() async {
    if (Platform.isAndroid) {
      // Public Download folder works for app-created files on most devices;
      // fall back to the app's own external dir under scoped storage.
      final public = Directory('/storage/emulated/0/Download');
      try {
        final probe = File(
            '${public.path}/.ytdl_probe_${DateTime.now().millisecondsSinceEpoch}');
        probe.writeAsStringSync('x');
        probe.deleteSync();
        return public;
      } catch (_) {
        final dir = await getExternalStorageDirectory() ??
            await getApplicationDocumentsDirectory();
        return dir;
      }
    }
    final dir = await getDownloadsDirectory();
    if (dir != null) return dir;
    return getApplicationDocumentsDirectory();
  }

  String _sanitize(String name) {
    var s = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
    if (s.length > 120) s = s.substring(0, 120);
    return s.isEmpty ? 'youtube_download' : s;
  }

  String _uniquePath(String dir, String base, String ext) {
    var path = '$dir/$base.$ext';
    var n = 1;
    while (File(path).existsSync()) {
      path = '$dir/$base ($n).$ext';
      n++;
    }
    return path;
  }

  void dispose() => _yt.close();
}
