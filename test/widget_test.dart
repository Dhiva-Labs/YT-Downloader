import 'package:flutter_test/flutter_test.dart';
import 'package:yt_downloader/main.dart';

void main() {
  testWidgets('splash shows branding then lands on home',
      (WidgetTester tester) async {
    // runAsync so real async work (the ffmpeg probe via Process.run and the
    // splash's navigation timer) can actually run.
    await tester.runAsync(() async {
      await tester.pumpWidget(const YtDownloaderApp());
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();

      expect(find.text('YT-Downloader'), findsOneWidget);
      expect(find.text('by DhivaLabs'), findsOneWidget);

      // Wait out the splash timer, then let the fade transition finish.
      await Future<void>.delayed(const Duration(milliseconds: 2300));
    });
    await tester.pumpAndSettle();

    expect(find.text('Paste a YouTube video or Shorts link…'), findsOneWidget);
    expect(find.text('Fetch'), findsOneWidget);
  });
}
