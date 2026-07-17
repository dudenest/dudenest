import 'package:flutter/material.dart';
import '../../core/network/relay_client.dart';
import 'date_group_model.dart';
import 'date_scrubbar.dart';
import 'gallery_settings.dart';
import 'justified_grid.dart';
import 'masonry_grid.dart';

// GalleryScreen — replaces _buildGrid in relay_screen for the Files tab.
// Supports Justified (Google Photos), Masonry (Pinterest), Square grid and List modes.
class GalleryScreen extends StatefulWidget {
  final List<Map<String, dynamic>> files;
  final RelayClient relay;
  final GallerySettings settings;
  final Set<String> selected;
  final bool selectionMode;
  final void Function(String id, String name) onOpen;
  final void Function(String id) onToggleSelect;
  final bool Function(String name) isImage;
  final bool Function(String name) isVideo;
  final IconData Function(String name) fileIcon;

  const GalleryScreen({
    super.key,
    required this.files,
    required this.relay,
    required this.settings,
    required this.selected,
    required this.selectionMode,
    required this.onOpen,
    required this.onToggleSelect,
    required this.isImage,
    required this.isVideo,
    required this.fileIcon,
  });

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final _scrollCtrl = ScrollController();
  final _groupOffsets = <String, double>{};
  late List<DateGroup> _groups;

  @override
  void initState() {
    super.initState();
    _buildGroups();
  }

  @override
  void didUpdateWidget(GalleryScreen old) {
    super.didUpdateWidget(old);
    if (old.files != widget.files || old.settings.groupByDate != widget.settings.groupByDate) {
      _buildGroups();
    }
    if (old.settings.viewMode != widget.settings.viewMode) {
      _groupOffsets.clear();
      if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(0);
    }
  }

  void _buildGroups() {
    if (widget.settings.groupByDate) {
      _groups = DateGroupModel.group(widget.files);
    } else {
      _groups = [DateGroup(label: '', date: DateTime.now(), files: widget.files)];
    }
  }

  @override
  void dispose() { _scrollCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final showScrubbar = s.showDateScrubbar && s.viewMode == GalleryViewMode.justified;
    return Stack(children: [
      Padding(
        padding: EdgeInsets.only(right: showScrubbar ? 30 : 0),
        child: _buildContent(s),
      ),
      if (showScrubbar && _groups.isNotEmpty)
        Positioned(
          top: 0, bottom: 0, right: 0, width: 30,
          child: DateScrubbar(
            groups: _groups,
            scrollController: _scrollCtrl,
            groupOffsets: _groupOffsets,
          ),
        ),
    ]);
  }

  Widget _buildContent(GallerySettings s) {
    switch (s.viewMode) {
      case GalleryViewMode.justified:
        return JustifiedGrid(
          groups: _groups, settings: s, relay: widget.relay,
          scrollController: _scrollCtrl, groupOffsets: _groupOffsets,
          onOpen: widget.onOpen, onToggleSelect: widget.onToggleSelect,
          selected: widget.selected, selectionMode: widget.selectionMode,
          isImage: widget.isImage, isVideo: widget.isVideo, fileIcon: widget.fileIcon,
        );
      case GalleryViewMode.masonry:
        return MasonryGrid(
          groups: _groups, settings: s, relay: widget.relay,
          scrollController: _scrollCtrl, groupOffsets: _groupOffsets,
          onOpen: widget.onOpen, onToggleSelect: widget.onToggleSelect,
          selected: widget.selected, selectionMode: widget.selectionMode,
          isImage: widget.isImage, isVideo: widget.isVideo, fileIcon: widget.fileIcon,
        );
      case GalleryViewMode.square:
        return _SquareGrid(
          groups: _groups, settings: s, relay: widget.relay,
          scrollController: _scrollCtrl, groupOffsets: _groupOffsets,
          onOpen: widget.onOpen, onToggleSelect: widget.onToggleSelect,
          selected: widget.selected, selectionMode: widget.selectionMode,
          isImage: widget.isImage, isVideo: widget.isVideo, fileIcon: widget.fileIcon,
        );
      case GalleryViewMode.list:
        return _ListView(
          groups: _groups, settings: s, relay: widget.relay,
          scrollController: _scrollCtrl,
          onOpen: widget.onOpen, onToggleSelect: widget.onToggleSelect,
          selected: widget.selected, selectionMode: widget.selectionMode,
          isImage: widget.isImage, fileIcon: widget.fileIcon,
        );
    }
  }
}

// ─── Square grid (original 3-column fixed grid, preserved as option) ──────────

class _SquareGrid extends StatelessWidget {
  final List<DateGroup> groups;
  final GallerySettings settings;
  final RelayClient relay;
  final ScrollController scrollController;
  final Map<String, double> groupOffsets;
  final void Function(String id, String name) onOpen;
  final void Function(String id) onToggleSelect;
  final Set<String> selected;
  final bool selectionMode;
  final bool Function(String name) isImage;
  final bool Function(String name) isVideo;
  final IconData Function(String name) fileIcon;

  const _SquareGrid({
    required this.groups, required this.settings, required this.relay,
    required this.scrollController, required this.groupOffsets,
    required this.onOpen, required this.onToggleSelect,
    required this.selected, required this.selectionMode,
    required this.isImage, required this.isVideo, required this.fileIcon,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: scrollController,
      slivers: groups.expand((group) => [
        if (settings.showDateHeaders)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
              child: Text(group.label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 4),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, mainAxisSpacing: 1, crossAxisSpacing: 1,
            ),
            delegate: SliverChildBuilderDelegate((ctx, i) {
              final f = group.files[i];
              final id = f['file_id'] as String? ?? '';
              final name = f['name'] as String? ?? id;
              final isSelected = selected.contains(id);
              return GestureDetector(
                onTap: () => selectionMode ? onToggleSelect(id) : onOpen(id, name),
                onLongPress: () => onToggleSelect(id),
                child: Stack(fit: StackFit.expand, children: [
                  (isImage(name) || isVideo(name))
                      ? Image(image: relay.thumbnail(id), fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(color: const Color(0xFF0D1117),
                              child: const Center(child: Icon(Icons.broken_image, color: Color(0xFF404040)))),
                          loadingBuilder: (_, child, p) => p == null ? child
                              : Container(color: const Color(0xFF0D1117),
                                  child: const Center(child: CircularProgressIndicator(strokeWidth: 1))))
                      : Container(color: const Color(0xFF111827),
                          child: Center(child: Icon(fileIcon(name), size: 36, color: const Color(0xFF6080A0)))),
                  if (isVideo(name))
                    const Center(child: Icon(Icons.play_circle_outline, color: Colors.white, size: 36,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 8)])),
                  if (selectionMode) AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    color: isSelected ? Colors.black54 : Colors.black26,
                    child: isSelected
                        ? const Center(child: Icon(Icons.check_circle, color: Colors.white, size: 36))
                        : Padding(padding: const EdgeInsets.all(5),
                            child: Align(alignment: Alignment.topRight,
                              child: Container(width: 22, height: 22,
                                decoration: BoxDecoration(shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white70, width: 2))))),
                  ),
                ]),
              );
            }, childCount: group.files.length),
          ),
        ),
      ]).toList(),
    );
  }
}

// ─── List view ────────────────────────────────────────────────────────────────

class _ListView extends StatelessWidget {
  final List<DateGroup> groups;
  final GallerySettings settings;
  final RelayClient relay;
  final ScrollController scrollController;
  final void Function(String id, String name) onOpen;
  final void Function(String id) onToggleSelect;
  final Set<String> selected;
  final bool selectionMode;
  final bool Function(String name) isImage;
  final IconData Function(String name) fileIcon;

  const _ListView({
    required this.groups, required this.settings, required this.relay,
    required this.scrollController,
    required this.onOpen, required this.onToggleSelect,
    required this.selected, required this.selectionMode,
    required this.isImage, required this.fileIcon,
  });

  String _fmtSize(dynamic bytes) {
    if (bytes == null) return '?';
    final n = bytes as num;
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allTiles = <Widget>[];
    for (final group in groups) {
      if (settings.showDateHeaders && group.label.isNotEmpty) {
        allTiles.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(group.label,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        ));
      }
      for (final f in group.files) {
        final id = f['file_id'] as String? ?? '';
        final name = f['name'] as String? ?? id;
        final isSelected = selected.contains(id);
        allTiles.add(ListTile(
          selected: isSelected,
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: isImage(name)
                ? Image(image: relay.thumbnail(id),
                    width: 44, height: 44, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => SizedBox(width: 44, height: 44,
                        child: Center(child: Icon(fileIcon(name)))))
                : SizedBox(width: 44, height: 44, child: Center(child: Icon(fileIcon(name)))),
          ),
          title: Text(name, overflow: TextOverflow.ellipsis),
          subtitle: Text(_fmtSize(f['size'])),
          trailing: selectionMode
              ? Icon(isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: isSelected ? theme.colorScheme.primary : Colors.grey)
              : null,
          onTap: () => selectionMode ? onToggleSelect(id) : onOpen(id, name),
          onLongPress: () => onToggleSelect(id),
        ));
      }
    }
    return ListView(controller: scrollController, children: allTiles);
  }
}
