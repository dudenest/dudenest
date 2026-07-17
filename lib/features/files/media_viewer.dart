import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/auth/auth_service.dart';
import '../../core/auth/web_utils.dart';
import '../../core/network/relay_client.dart';
import 'video_player_widget.dart';

// MediaViewer: fullscreen viewer — progressive image loading, inline video, swipe/keyboard nav, overlay, info panel.
class MediaViewer extends StatefulWidget {
  final List<Map<String, dynamic>> files;
  final int initialIndex;
  final RelayClient relay;
  final VoidCallback? onDelete;

  const MediaViewer({
    super.key,
    required this.files,
    required this.initialIndex,
    required this.relay,
    this.onDelete,
  });

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> with TickerProviderStateMixin {
  late final PageController _pageCtrl;
  late int _currentIndex;
  bool _overlayVisible = true;
  bool _infoPanelOpen = false;
  Timer? _overlayTimer;
  late final AnimationController _overlayAnim;

  static const _imageExts = {'jpg','jpeg','png','gif','webp','bmp','heic','heif'};
  static const _videoExts = {'mp4','mov','avi','mkv','webm','m4v','3gp','wmv','flv'};

  bool _isImage(String name) => _imageExts.contains(name.split('.').last.toLowerCase());
  bool _isVideo(String name) => _videoExts.contains(name.split('.').last.toLowerCase());

  bool get _curIsVideo => _isVideo(_curName);

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.files.length - 1);
    _pageCtrl = PageController(initialPage: _currentIndex);
    _overlayAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 220), value: 1.0);
    _scheduleOverlayHide();
    WidgetsBinding.instance.addPostFrameCallback((_) => _preloadNeighbors(_currentIndex));
  }

  @override
  void dispose() {
    _overlayTimer?.cancel();
    _pageCtrl.dispose();
    _overlayAnim.dispose();
    super.dispose();
  }

  void _scheduleOverlayHide() {
    _overlayTimer?.cancel();
    // Videos: 8s before hide (mouse movement resets via MouseRegion); images: 4s
    final delay = _curIsVideo ? const Duration(seconds: 8) : const Duration(seconds: 4);
    _overlayTimer = Timer(delay, () {
      if (mounted && _overlayVisible) _hideOverlay();
    });
  }

  void _showOverlay() {
    if (!_overlayVisible) setState(() => _overlayVisible = true);
    _overlayAnim.forward();
    _scheduleOverlayHide();
  }

  void _hideOverlay() {
    if (_overlayVisible) setState(() => _overlayVisible = false);
    _overlayAnim.reverse();
  }

  void _toggleOverlay() => _overlayVisible ? _hideOverlay() : _showOverlay();

  void _prevPage() {
    if (_currentIndex > 0) {
      _pageCtrl.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  void _nextPage() {
    if (_currentIndex < widget.files.length - 1) {
      _pageCtrl.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) { _nextPage(); _showOverlay(); return KeyEventResult.handled; }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft)  { _prevPage(); _showOverlay(); return KeyEventResult.handled; }
    if (event.logicalKey == LogicalKeyboardKey.escape)     { Navigator.pop(context); return KeyEventResult.handled; }
    return KeyEventResult.ignored;
  }

  void _preloadNeighbors(int index) {
    for (final offset in [-1, 1]) {
      final i = index + offset;
      if (i < 0 || i >= widget.files.length) continue;
      final f = widget.files[i];
      final id = f['file_id'] as String? ?? '';
      final name = f['name'] as String? ?? '';
      if (_imageExts.contains(name.split('.').last.toLowerCase())) {
        precacheImage(widget.relay.preview(id), context);
      }
    }
  }

  Map<String, dynamic> get _cur => widget.files[_currentIndex];
  String get _curId => _cur['file_id'] as String? ?? '';
  String get _curName => _cur['name'] as String? ?? _curId;

  // Video URL embeds JWT token as query param — <video> element can't set Authorization header.
  String _videoUrl(String fileId) {
    final token = Uri.encodeComponent(AuthService().token ?? '');
    return '${widget.relay.baseUrl}/files/$fileId?token=$token';
  }

  String _formatSize(dynamic bytes) {
    if (bytes == null) return '?';
    final n = bytes as num;
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  String _formatDate(String iso) {
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    return '${dt.day}.${dt.month.toString().padLeft(2,'0')}.${dt.year}'
        '  ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
  }

  Future<void> _download() async {
    try {
      final bytes = await widget.relay.downloadFile(_curId);
      await downloadBytes(_curName, bytes);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete file'),
        content: Text('Delete "$_curName"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.relay.deleteFile(_curId);
      widget.onDelete?.call();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: MouseRegion(
          onHover: (_) => _showOverlay(), // show overlay on any mouse movement (including over video)
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _toggleOverlay,
            child: Stack(children: [
              PageView.builder(
                controller: _pageCtrl,
                itemCount: widget.files.length,
                onPageChanged: (i) {
                  setState(() { _currentIndex = i; _infoPanelOpen = false; });
                  _showOverlay();
                  _preloadNeighbors(i);
                },
                itemBuilder: (ctx, i) {
                  final f = widget.files[i];
                  final id = f['file_id'] as String? ?? '';
                  final name = f['name'] as String? ?? id;
                  if (_isVideo(name)) {
                    return VideoPlayerWidget(videoUrl: _videoUrl(id), headers: widget.relay.headers);
                  }
                  if (_isImage(name)) {
                    return _ProgressiveImage(
                      key: ValueKey(id),
                      fileId: id,
                      relay: widget.relay,
                      isActive: i == _currentIndex,
                      lqip: f['lqip'] as String?,
                    );
                  }
                  return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.insert_drive_file, size: 80, color: Colors.white38),
                    const SizedBox(height: 12),
                    Text(name, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                  ]));
                },
              ),
              // Overlay: fades in/out; IgnorePointer prevents button taps when hidden.
              AnimatedBuilder(
                animation: _overlayAnim,
                builder: (ctx, child) => IgnorePointer(
                  ignoring: _overlayAnim.value < 0.1,
                  child: Opacity(opacity: _overlayAnim.value, child: child),
                ),
                child: _buildOverlay(),
              ),
              // Info panel: slide in from right (always interactive, outside IgnorePointer)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                top: 0, bottom: 0,
                right: _infoPanelOpen ? 0 : -360,
                width: 320,
                child: _buildInfoPanel(),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay() {
    return Stack(children: [
      // Top + bottom gradient bars
      Column(children: [
        Container(
          decoration: const BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xCC000000), Colors.transparent],
          )),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(child: Text(_curName,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, shadows: [Shadow(blurRadius: 4)]),
                    overflow: TextOverflow.ellipsis)),
                IconButton(
                  icon: const Icon(Icons.info_outline, color: Colors.white70),
                  tooltip: 'Info',
                  onPressed: () { setState(() => _infoPanelOpen = !_infoPanelOpen); _showOverlay(); },
                ),
                IconButton(
                  icon: const Icon(Icons.download, color: Colors.white70),
                  tooltip: 'Download',
                  onPressed: _download,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.white54),
                  tooltip: 'Delete',
                  onPressed: _confirmDelete,
                ),
              ]),
            ),
          ),
        ),
        const Spacer(),
        Container(
          decoration: const BoxDecoration(gradient: LinearGradient(
            begin: Alignment.bottomCenter, end: Alignment.topCenter,
            colors: [Color(0x88000000), Colors.transparent],
          )),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(child: Text(
                '${_currentIndex + 1} / ${widget.files.length}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              )),
            ),
          ),
        ),
      ]),
      // Left nav arrow (prev)
      if (_currentIndex > 0)
        Positioned(
          left: 0, top: 0, bottom: 0, width: 80,
          child: Center(
            child: _NavButton(icon: Icons.chevron_left, onTap: _prevPage),
          ),
        ),
      // Right nav arrow (next)
      if (_currentIndex < widget.files.length - 1)
        Positioned(
          right: 0, top: 0, bottom: 0, width: 80,
          child: Center(
            child: _NavButton(icon: Icons.chevron_right, onTap: _nextPage),
          ),
        ),
    ]);
  }

  Widget _buildInfoPanel() {
    final f = _cur;
    final name = f['name'] as String? ?? '';
    final size = f['size'];
    final created = f['created'] as String? ?? '';
    final takenAt = f['taken_at'] as String?;
    final w = f['width'] as int? ?? 0;
    final h = f['height'] as int? ?? 0;
    return Material(
      color: const Color(0xEE0D1117),
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 4, 0),
            child: Row(children: [
              const Text('File info', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => setState(() => _infoPanelOpen = false)),
            ]),
          ),
          const Divider(color: Color(0x33FFFFFF), height: 1),
          const SizedBox(height: 8),
          _infoRow('Name', name),
          _infoRow('Size', _formatSize(size)),
          if (w > 0) _infoRow('Dimensions', '${w}×$h px'),
          if (takenAt != null) _infoRow('Photo taken', _formatDate(takenAt)),
          if (created.isNotEmpty) _infoRow('Uploaded', _formatDate(created)),
          _infoRow('File ID', _curId.length > 16 ? '${_curId.substring(0, 16)}…' : _curId),
        ]),
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 92, child: Text(label, style: const TextStyle(color: Color(0xFF8899AA), fontSize: 12))),
      Expanded(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 12))),
    ]),
  );
}

// Circular nav button for prev/next arrows
class _NavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _NavButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 44, height: 44,
      decoration: const BoxDecoration(color: Color(0x66000000), shape: BoxShape.circle),
      child: Icon(icon, color: Colors.white, size: 28),
    ),
  );
}

// ─── Progressive image: LQIP blur → 800px preview → original with 300ms crossfades ──
// Layer 0 (LQIP) and loading indicator replaced the square thumbnail — avoids 1:1 artifact.
class _ProgressiveImage extends StatefulWidget {
  final String fileId;
  final RelayClient relay;
  final bool isActive; // true = start loading original; false = load only preview
  final String? lqip;  // data:image/jpeg;base64,... tiny blur placeholder

  const _ProgressiveImage({
    super.key,
    required this.fileId,
    required this.relay,
    required this.isActive,
    this.lqip,
  });

  @override
  State<_ProgressiveImage> createState() => _ProgressiveImageState();
}

class _ProgressiveImageState extends State<_ProgressiveImage> {
  bool _previewLoaded = false;
  bool _originalLoaded = false;
  final _xformCtrl = TransformationController();
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _xformCtrl.addListener(_onTransform);
  }

  void _onTransform() {
    final s = _xformCtrl.value.getMaxScaleOnAxis();
    final z = s > 1.05;
    if (z != _zoomed) setState(() => _zoomed = z);
  }

  @override
  void dispose() {
    _xformCtrl.removeListener(_onTransform);
    _xformCtrl.dispose();
    super.dispose();
  }


  Uint8List? _lqipBytes() {
    final lqip = widget.lqip;
    if (lqip == null || lqip.isEmpty) return null;
    try {
      final b64 = lqip.contains(',') ? lqip.split(',').last : lqip;
      return base64Decode(b64);
    } catch (_) { return null; }
  }

  @override
  Widget build(BuildContext context) {
    final lqipBytes = _lqipBytes();
    final anyLoaded = _previewLoaded || _originalLoaded;
    // panEnabled: false at 1x so PageView captures horizontal swipes; true when zoomed to allow panning.
    return InteractiveViewer(
      transformationController: _xformCtrl,
      panEnabled: _zoomed,
      minScale: 0.8, maxScale: 8.0,
      child: Stack(fit: StackFit.expand, children: [
        // Layer 0: placeholder while preview loads — LQIP blur or loading spinner
        if (!anyLoaded)
          lqipBytes != null
              ? Image.memory(lqipBytes, fit: BoxFit.contain, gaplessPlayback: true)
              : const Center(child: CircularProgressIndicator(color: Colors.white38, strokeWidth: 1.5)),
        // Layer 1: 800px preview (aspect-ratio-correct) — crossfade 300ms
        AnimatedOpacity(
          opacity: _previewLoaded ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: Image(image: widget.relay.preview(widget.fileId), fit: BoxFit.contain,
            frameBuilder: (ctx, child, frame, sync) {
              if ((frame != null || sync) && !_previewLoaded) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _previewLoaded = true);
                });
              }
              return child;
            },
            errorBuilder: (_, __, ___) {
              // Preview not available — mark as loaded so spinner disappears, original will show
              if (!_previewLoaded) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _previewLoaded = true);
                });
              }
              return const SizedBox.shrink();
            }),
        ),
        // Layer 2: original full resolution — crossfade 300ms, only load for active page
        if (widget.isActive) AnimatedOpacity(
          opacity: _originalLoaded ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: Image(image: widget.relay.original(widget.fileId), fit: BoxFit.contain,
            frameBuilder: (ctx, child, frame, sync) {
              if ((frame != null || sync) && !_originalLoaded) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _originalLoaded = true);
                });
              }
              return child;
            },
            errorBuilder: (_, __, ___) => const SizedBox.shrink()),
        ),
      ]),
    );
  }
}
