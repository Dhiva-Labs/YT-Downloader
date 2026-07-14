import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'download_manager.dart';
import 'main.dart';
import 'yt_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _service = YtService();
  late final DownloadManager _manager = DownloadManager(_service);
  final _urlController = TextEditingController();

  bool _fetching = false;
  String? _error;
  FetchResult? _result;
  bool _audioMode = false;
  DownloadOption? _selected;
  bool _ffmpeg = false;

  @override
  void initState() {
    super.initState();
    _manager.addListener(_onManagerChanged);
    _service.ffmpegAvailable.then((v) {
      if (mounted) setState(() => _ffmpeg = v);
    });
  }

  void _onManagerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _manager.removeListener(_onManagerChanged);
    _urlController.dispose();
    _service.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) {
      _urlController.text = text;
      _fetch();
    }
  }

  Future<void> _fetch() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _fetching = true;
      _error = null;
      _result = null;
      _selected = null;
    });
    try {
      final result = await _service.fetchInfo(url);
      if (!mounted) return;
      setState(() {
        _result = result;
        _fetching = false;
        final options =
            _audioMode ? result.audioOptions : result.videoOptions;
        _selected = options.isNotEmpty ? options.first : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fetching = false;
        _error = 'Could not fetch video info. Check the link.\n($e)';
      });
    }
  }

  void _startDownload() {
    final result = _result;
    final option = _selected;
    if (result == null || option == null) return;
    _manager.start(result.video, option, onDone: _showDonePopup);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Added "${result.video.title}" to downloads'),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _showDonePopup(DownloadTask task) {
    if (!mounted) return;
    final theme = Theme.of(context);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(Icons.check_circle_rounded,
            color: theme.colorScheme.primary, size: 48),
        title: const Text('Download complete'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              task.video.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              'Saved to ${task.path}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          if (!Platform.isAndroid && !Platform.isIOS)
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _showInFolder(task.path!);
              },
              icon: const Icon(Icons.folder_open),
              label: const Text('Show in folder'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showInFolder(String path) {
    final dir = File(path).parent.path;
    if (Platform.isLinux) {
      Process.run('xdg-open', [dir]);
    } else if (Platform.isWindows) {
      Process.run('explorer', [dir]);
    } else if (Platform.isMacOS) {
      Process.run('open', [dir]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
              theme.colorScheme.surface,
            ],
            stops: const [0, 0.35],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _buildHeader(theme),
                  const SizedBox(height: 16),
                  _buildUrlBar(),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _buildError(theme),
                  ],
                  if (_fetching) ...[
                    const SizedBox(height: 48),
                    const Center(child: CircularProgressIndicator()),
                    const SizedBox(height: 12),
                    const Center(child: Text('Fetching video info…')),
                  ],
                  if (_result != null) ...[
                    const SizedBox(height: 16),
                    _buildVideoCard(theme, _result!.video),
                    const SizedBox(height: 16),
                    _buildModeSelector(),
                    const SizedBox(height: 12),
                    _buildOptions(theme),
                    const SizedBox(height: 16),
                    _buildDownloadButton(theme),
                  ],
                  if (_result == null && !_fetching && _error == null)
                    _buildEmptyHint(theme),
                  if (_manager.tasks.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _buildDownloadsPanel(theme),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFE53935), Color(0xFFB71C1C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE53935).withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.download_rounded,
              color: Colors.white, size: 26),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('YT-Downloader',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              Text('by DhivaLabs • your format, your quality',
                  style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        ValueListenableBuilder<ThemeMode>(
          valueListenable: themeMode,
          builder: (context, mode, _) => IconButton.filledTonal(
            tooltip: 'Theme: ${mode.name}',
            onPressed: cycleThemeMode,
            icon: Icon(switch (mode) {
              ThemeMode.system => Icons.brightness_auto,
              ThemeMode.light => Icons.light_mode,
              ThemeMode.dark => Icons.dark_mode,
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildUrlBar() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _urlController,
            enabled: !_fetching,
            decoration: InputDecoration(
              hintText: 'Paste a YouTube video or Shorts link…',
              prefixIcon: const Icon(Icons.link),
              suffixIcon: IconButton(
                tooltip: 'Paste from clipboard',
                icon: const Icon(Icons.content_paste),
                onPressed: _fetching ? null : _paste,
              ),
            ),
            onSubmitted: (_) => _fetch(),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _fetching ? null : _fetch,
          icon: const Icon(Icons.search),
          label: const Text('Fetch'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          ),
        ),
      ],
    );
  }

  Widget _buildError(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _error!,
        style: TextStyle(color: theme.colorScheme.onErrorContainer),
      ),
    );
  }

  Widget _buildVideoCard(ThemeData theme, Video video) {
    final d = video.duration;
    final duration = d == null
        ? ''
        : [
            if (d.inHours > 0) d.inHours.toString(),
            d.inMinutes.remainder(60).toString().padLeft(2, '0'),
            d.inSeconds.remainder(60).toString().padLeft(2, '0'),
          ].join(':');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  video.thumbnails.highResUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.ondemand_video, size: 48),
                  ),
                ),
              ),
              if (duration.isNotEmpty)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(duration,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(video.title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.person_outline,
                        size: 16, color: theme.colorScheme.outline),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(video.author,
                          style: theme.textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    return SegmentedButton<bool>(
      style: SegmentedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      segments: const [
        ButtonSegment(
            value: false,
            label: Text('Video'),
            icon: Icon(Icons.videocam_outlined)),
        ButtonSegment(
            value: true,
            label: Text('Audio only'),
            icon: Icon(Icons.music_note_outlined)),
      ],
      selected: {_audioMode},
      onSelectionChanged: (sel) {
        setState(() {
          _audioMode = sel.first;
          final options =
              _audioMode ? _result!.audioOptions : _result!.videoOptions;
          _selected = options.isNotEmpty ? options.first : null;
        });
      },
    );
  }

  Widget _buildOptions(ThemeData theme) {
    final options =
        _audioMode ? _result!.audioOptions : _result!.videoOptions;
    if (options.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No streams available for this mode.'),
      );
    }
    return Column(
      children: [
        for (final option in options)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _OptionTile(
              option: option,
              selected: option == _selected,
              onTap: () => setState(() => _selected = option),
            ),
          ),
      ],
    );
  }

  Widget _buildDownloadButton(ThemeData theme) {
    return FilledButton.icon(
      onPressed: _selected == null ? null : _startDownload,
      icon: const Icon(Icons.download_rounded),
      label: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(
          _audioMode ? 'Download audio' : 'Download video',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Widget _buildDownloadsPanel(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Downloads',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            if (_manager.tasks.any((t) => t.isFinished))
              TextButton(
                onPressed: _manager.clearFinished,
                child: const Text('Clear finished'),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (final task in _manager.tasks)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _TaskTile(
              task: task,
              onCancel: task.status == TaskStatus.running
                  ? () => task.cancel()
                  : null,
              onOpenFolder: task.status == TaskStatus.done &&
                      !Platform.isAndroid &&
                      !Platform.isIOS
                  ? () => _showInFolder(task.path!)
                  : null,
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyHint(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 64),
      child: Column(
        children: [
          Icon(Icons.smart_display_outlined,
              size: 72, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text('Paste a YouTube video or Shorts link to get started',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            _ffmpeg
                ? 'MP3, 1080p+ merges and audio-as-video enabled'
                : 'Install ffmpeg to unlock 1080p+, MP3 and audio-as-video',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final DownloadOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final icon = option.blankVideo
        ? Icons.music_video_outlined
        : option.mp3Bitrate != null
            ? Icons.library_music_outlined
            : option.isAudio
                ? Icons.audiotrack
                : Icons.high_quality_outlined;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: selected
            ? scheme.primaryContainer.withValues(alpha: 0.55)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? scheme.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: selected
                      ? scheme.primary
                      : scheme.surfaceContainerHighest,
                  child: Icon(icon,
                      size: 20,
                      color: selected
                          ? scheme.onPrimary
                          : scheme.onSurfaceVariant),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(option.label,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      Text(
                        option.needsFfmpeg
                            ? '${option.sizeText} • processed with ffmpeg'
                            : option.sizeText,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle, color: scheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.task,
    this.onCancel,
    this.onOpenFolder,
  });

  final DownloadTask task;
  final VoidCallback? onCancel;
  final VoidCallback? onOpenFolder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (icon, color) = switch (task.status) {
      TaskStatus.running => (Icons.downloading, scheme.primary),
      TaskStatus.done => (Icons.check_circle, Colors.green),
      TaskStatus.error => (Icons.error, scheme.error),
      TaskStatus.cancelled => (Icons.cancel, scheme.outline),
    };
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(task.video.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      Text(
                        switch (task.status) {
                          TaskStatus.running => task.phase,
                          TaskStatus.done => 'Saved to ${task.path}',
                          TaskStatus.error =>
                            task.error ?? 'Download failed',
                          TaskStatus.cancelled => 'Cancelled',
                        },
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Text(' ${task.option.label.split('•').first.trim()}',
                    style: theme.textTheme.labelSmall),
                if (onCancel != null)
                  IconButton(
                    tooltip: 'Cancel',
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: onCancel,
                  ),
                if (onOpenFolder != null)
                  IconButton(
                    tooltip: 'Show in folder',
                    icon: const Icon(Icons.folder_open, size: 20),
                    onPressed: onOpenFolder,
                  ),
              ],
            ),
            if (task.status == TaskStatus.running) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                    value: task.progress, minHeight: 8),
              ),
              const SizedBox(height: 4),
              Text('${(task.progress * 100).toStringAsFixed(0)}%',
                  style: theme.textTheme.labelSmall),
            ],
          ],
        ),
      ),
    );
  }
}
