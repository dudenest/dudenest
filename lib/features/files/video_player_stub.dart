import 'package:flutter/material.dart';

// Stub for non-web platforms: shows download hint instead of video player.
class VideoPlayerWidget extends StatelessWidget {
  final String videoUrl;
  final Map<String, String> headers;
  const VideoPlayerWidget({super.key, required this.videoUrl, required this.headers});

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.play_circle_outline, size: 80, color: Colors.white54),
      SizedBox(height: 12),
      Text('Download to play video', style: TextStyle(color: Colors.white54, fontSize: 14)),
    ]),
  );
}
