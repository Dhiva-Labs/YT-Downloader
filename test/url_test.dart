import 'package:flutter_test/flutter_test.dart';
import 'package:yt_downloader/yt_service.dart';

void main() {
  group('YtService.normalizeUrl', () {
    test('rewrites a Shorts share link with tracking params', () {
      expect(
        YtService.normalizeUrl(
            'https://youtube.com/shorts/yIVRs6YSbOM?si=AbC123xYz'),
        'https://www.youtube.com/watch?v=yIVRs6YSbOM',
      );
    });

    test('rewrites a plain Shorts link', () {
      expect(
        YtService.normalizeUrl('https://www.youtube.com/shorts/yIVRs6YSbOM'),
        'https://www.youtube.com/watch?v=yIVRs6YSbOM',
      );
    });

    test('rewrites a live replay link', () {
      expect(
        YtService.normalizeUrl(
            'https://www.youtube.com/live/dQw4w9WgXcQ?feature=shared'),
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
    });

    test('leaves normal watch and youtu.be links untouched', () {
      const watch = 'https://www.youtube.com/watch?v=jNQXAC9IVRw';
      const short = 'https://youtu.be/jNQXAC9IVRw?si=xyz';
      expect(YtService.normalizeUrl(watch), watch);
      expect(YtService.normalizeUrl(short), short);
    });
  });
}
