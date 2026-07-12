// ignore_for_file: avoid_print — CLI smoke-test script.
// Live smoke test of the youtube_explode_dart pipeline used by YtService.
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Future<void> main() async {
  final yt = YoutubeExplode();
  try {
    // "Me at the zoo" — short, stable test video.
    final video = await yt.videos.get('https://www.youtube.com/watch?v=jNQXAC9IVRw');
    print('TITLE: ${video.title} (${video.duration})');

    final manifest = await yt.videos.streamsClient
        .getManifest(video.id, ytClients: [
      YoutubeApiClient.androidVr,
      YoutubeApiClient.ios,
    ]);
    print('MUXED: ${manifest.muxed.map((s) => '${s.qualityLabel}/${s.container.name}').toList()}');
    print('VIDEO-ONLY: ${manifest.videoOnly.length} streams, '
        'best ${manifest.videoOnly.isEmpty ? '-' : manifest.videoOnly.sortByVideoQuality().first.qualityLabel}');
    print('AUDIO-ONLY: ${manifest.audioOnly.map((s) => '${(s.bitrate.bitsPerSecond / 1000).round()}kbps/${s.container.name}').toList()}');

    final audio = manifest.audioOnly.withHighestBitrate();
    var received = 0;
    final out = File('/tmp/claude-1000/-home-dhivakar-dhiva-labs-sonic-flow/31b242ec-79c9-4931-9ee1-dba0322f79b2/scratchpad/sample_audio.bin');
    final sink = out.openWrite();
    await for (final chunk in yt.videos.streamsClient.get(audio)) {
      sink.add(chunk);
      received += chunk.length;
    }
    await sink.flush();
    await sink.close();
    print('DOWNLOADED: $received bytes of ${audio.size.totalBytes} expected');
    print(received == audio.size.totalBytes ? 'PASS' : 'SIZE MISMATCH');
  } finally {
    yt.close();
  }
}
