import 'dart:async';

import 'package:flutter/material.dart';
import 'package:inboxplus_storage/inboxplus_storage.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class MediaPreviewDialog extends StatefulWidget {
  const MediaPreviewDialog({super.key, required this.attachment, this.onSave});

  final AttachmentRecord attachment;
  final Future<void> Function()? onSave;

  @override
  State<MediaPreviewDialog> createState() => _MediaPreviewDialogState();
}

class _MediaPreviewDialogState extends State<MediaPreviewDialog> {
  late final Player _player;
  late final VideoController _video;
  StreamSubscription<String>? _errors;
  bool _failed = false;

  bool get _audio =>
      widget.attachment.kind == 'audio' ||
      (widget.attachment.mimeType?.startsWith('audio/') ?? false);

  @override
  void initState() {
    super.initState();
    _player = Player();
    _video = VideoController(_player);
    _errors = _player.stream.error.listen((_) {
      if (mounted) setState(() => _failed = true);
    });
    _open();
  }

  Future<void> _open() async {
    try {
      await _player.open(
        Media(Uri.file(widget.attachment.localPath!).toString()),
      );
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _errors?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close preview',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close, semanticLabel: 'Close preview'),
        ),
        title: Text(widget.attachment.fileName ?? (_audio ? 'Audio' : 'Video')),
        actions: [
          if (widget.onSave != null)
            TextButton(onPressed: widget.onSave, child: const Text('Save As…')),
        ],
      ),
      body: _failed
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'This media could not be played. The downloaded file is still saved on this device.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : _audio
          ? _audioControls(context)
          : Center(child: Video(controller: _video)),
    ),
  );

  Widget _audioControls(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.headphones_outlined,
              size: 80,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 30),
            Text(
              widget.attachment.fileName ?? 'Audio attachment',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 20),
            StreamBuilder<Duration>(
              stream: _player.stream.duration,
              initialData: _player.state.duration,
              builder: (context, duration) => StreamBuilder<Duration>(
                stream: _player.stream.position,
                initialData: _player.state.position,
                builder: (context, position) {
                  final total = duration.data?.inMilliseconds ?? 0;
                  final current = (position.data?.inMilliseconds ?? 0).clamp(
                    0,
                    total,
                  );
                  return Column(
                    children: [
                      Slider(
                        value: current.toDouble(),
                        max: total > 0 ? total.toDouble() : 1,
                        onChanged: total > 0
                            ? (value) => _player.seek(
                                Duration(milliseconds: value.round()),
                              )
                            : null,
                        semanticFormatterCallback: (value) =>
                            _duration(Duration(milliseconds: value.round())),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_duration(position.data ?? Duration.zero)),
                            Text(_duration(duration.data ?? Duration.zero)),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            StreamBuilder<bool>(
              stream: _player.stream.playing,
              initialData: _player.state.playing,
              builder: (context, playing) => IconButton.filled(
                iconSize: 32,
                padding: const EdgeInsets.all(16),
                tooltip: playing.data == true ? 'Pause' : 'Play',
                onPressed: _player.playOrPause,
                icon: Icon(
                  playing.data == true ? Icons.pause : Icons.play_arrow,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  String _duration(Duration value) =>
      '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
}
