import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import 'dart:ui_web' as ui_web;

// Web implementation: registers an HTMLVideoElement via PlatformViewRegistry.
// Token must be embedded in videoUrl as ?token=... since <video> can't send custom headers.
class VideoPlayerWidget extends StatefulWidget {
  final String videoUrl;
  final Map<String, String> headers; // not used on web (token is in URL)
  const VideoPlayerWidget(
      {super.key, required this.videoUrl, required this.headers});

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late final String _viewType;
  web.HTMLVideoElement? _video;

  @override
  void initState() {
    super.initState();
    _viewType =
        'dudenest-video-${widget.videoUrl.hashCode}-${DateTime.now().microsecondsSinceEpoch}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) {
      final video = web.HTMLVideoElement()
        ..src = widget.videoUrl
        ..controls = true
        ..autoplay = true
        ..tabIndex = -1
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'contain'
        ..style.backgroundColor = 'black';
      _video = video;
      return video;
    });
  }

  @override
  void dispose() {
    final video = _video;
    if (video != null) {
      video.pause();
      video.blur();
      video.removeAttribute('src');
      video.load();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
