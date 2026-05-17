import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import 'dart:ui_web' as ui_web;

// Web implementation: registers an HTMLVideoElement via PlatformViewRegistry.
// Token must be embedded in videoUrl as ?token=... since <video> can't send custom headers.
class VideoPlayerWidget extends StatefulWidget {
  final String videoUrl;
  final Map<String, String> headers; // not used on web (token is in URL)
  const VideoPlayerWidget({super.key, required this.videoUrl, required this.headers});

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'dudenest-video-${widget.videoUrl.hashCode}-${DateTime.now().microsecondsSinceEpoch}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) {
      return web.HTMLVideoElement()
        ..src = widget.videoUrl
        ..controls = true
        ..autoplay = true
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'contain'
        ..style.backgroundColor = 'black';
    });
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
