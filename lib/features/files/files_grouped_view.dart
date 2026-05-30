// s329 Feature 5: renders /Files screen content as grouped sections per FilesViewSettings.
// Two-level nesting: primary group → secondary group → files. Each section is collapsible.
// Pure UI (no business logic) — grouping/sorting/filtering done by groupAndSort() pure helper.
import 'package:flutter/material.dart';
import 'files_view_settings.dart';

typedef FileTileBuilder = Widget Function(BuildContext context, Map<String, dynamic> file);

class FilesGroupedView extends StatelessWidget {
  final List<FilesGroup> groups;
  final FileTileBuilder itemBuilder;
  const FilesGroupedView({super.key, required this.groups, required this.itemBuilder});

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(32),
        child: Text('No files match the current filters', style: TextStyle(color: Colors.grey)),
      ));
    }
    return ListView.builder(
      itemCount: groups.length,
      itemBuilder: (ctx, i) => _buildGroup(ctx, groups[i], depth: 0),
    );
  }

  Widget _buildGroup(BuildContext ctx, FilesGroup g, {required int depth}) {
    final hasChildren = g.children.isNotEmpty;
    final headerStyle = TextStyle(
      fontWeight: depth == 0 ? FontWeight.w700 : FontWeight.w500,
      fontSize: depth == 0 ? 15 : 13,
      color: depth == 0 ? null : Colors.grey.shade700,
    );
    return ExpansionTile(
      key: PageStorageKey('${depth}_${g.label}'), // preserve expand/collapse state across rebuilds
      initiallyExpanded: true, // s329 Feature 5: open by default at both levels so user immediately sees content; collapse is manual
      tilePadding: EdgeInsets.only(left: 16.0 + depth * 16, right: 16),
      title: Text(g.label, style: headerStyle, overflow: TextOverflow.ellipsis),
      subtitle: Text('${g.fileCount} file${g.fileCount == 1 ? "" : "s"}',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      children: hasChildren
          ? g.children.map((c) => _buildGroup(ctx, c, depth: depth + 1)).toList()
          : g.files.map((f) => Padding(
              padding: EdgeInsets.only(left: (depth + 1) * 16.0),
              child: itemBuilder(ctx, f),
            )).toList(),
    );
  }
}

// FilesFilterSheet — bottom sheet allowing user to change group/sort/search/type filters in one place.
// Returns updated FilesViewSettings via Navigator.pop(ctx, newSettings); caller persists + re-renders.
class FilesFilterSheet extends StatefulWidget {
  final FilesViewSettings initial;
  const FilesFilterSheet({super.key, required this.initial});

  @override
  State<FilesFilterSheet> createState() => _FilesFilterSheetState();
}

class _FilesFilterSheetState extends State<FilesFilterSheet> {
  late FilesViewSettings _s;
  late TextEditingController _searchCtrl;

  @override
  void initState() {
    super.initState();
    _s = widget.initial;
    _searchCtrl = TextEditingController(text: _s.searchQuery);
  }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  String _modeLabel(FilesGroupMode m) => switch (m) {
    FilesGroupMode.account => 'Account', FilesGroupMode.date => 'Date',
    FilesGroupMode.type => 'Type', FilesGroupMode.none => 'No grouping',
  };
  String _sortLabel(FilesSortField f) => switch (f) {
    FilesSortField.date => 'Date', FilesSortField.name => 'Name',
    FilesSortField.size => 'Size', FilesSortField.type => 'Type',
  };

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    initialChildSize: 0.7, minChildSize: 0.4, maxChildSize: 0.95, expand: false,
    builder: (_, sc) => Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(controller: sc, children: [
        Row(children: [
          const Expanded(child: Text('Files view', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
          TextButton(onPressed: () => Navigator.pop(context, const FilesViewSettings()), child: const Text('Reset')),
          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        ]),
        const Divider(),
        const Text('Group by', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: DropdownButtonFormField<FilesGroupMode>(
            initialValue: _s.primaryGroup, isExpanded: true,
            decoration: const InputDecoration(labelText: 'Primary', border: OutlineInputBorder(), isDense: true),
            items: FilesGroupMode.values.map((m) => DropdownMenuItem(value: m, child: Text(_modeLabel(m)))).toList(),
            onChanged: (v) => setState(() => _s = _s.copyWith(primaryGroup: v ?? _s.primaryGroup)),
          )),
          const SizedBox(width: 8),
          Expanded(child: DropdownButtonFormField<FilesGroupMode>(
            initialValue: _s.secondaryGroup, isExpanded: true,
            decoration: const InputDecoration(labelText: 'Secondary', border: OutlineInputBorder(), isDense: true),
            items: FilesGroupMode.values.map((m) => DropdownMenuItem(value: m, child: Text(_modeLabel(m)))).toList(),
            onChanged: (v) => setState(() => _s = _s.copyWith(secondaryGroup: v ?? _s.secondaryGroup)),
          )),
        ]),
        const SizedBox(height: 16),
        const Text('Sort by', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: DropdownButtonFormField<FilesSortField>(
            initialValue: _s.sortField, isExpanded: true,
            decoration: const InputDecoration(labelText: 'Field', border: OutlineInputBorder(), isDense: true),
            items: FilesSortField.values.map((f) => DropdownMenuItem(value: f, child: Text(_sortLabel(f)))).toList(),
            onChanged: (v) => setState(() => _s = _s.copyWith(sortField: v ?? _s.sortField)),
          )),
          const SizedBox(width: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Desc'), icon: Icon(Icons.arrow_downward, size: 16)),
              ButtonSegment(value: true,  label: Text('Asc'),  icon: Icon(Icons.arrow_upward, size: 16)),
            ],
            selected: {_s.sortAscending},
            onSelectionChanged: (sel) => setState(() => _s = _s.copyWith(sortAscending: sel.first)),
          ),
        ]),
        const SizedBox(height: 16),
        const Text('Filter', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: _searchCtrl,
          decoration: const InputDecoration(
            labelText: 'Search by name', border: OutlineInputBorder(), isDense: true,
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => _s = _s.copyWith(searchQuery: v),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: [
          for (final type in const ['photo','video','document','archive','other'])
            FilterChip(
              label: Text(type[0].toUpperCase() + type.substring(1)),
              selected: _s.typeFilters.contains(type),
              onSelected: (on) => setState(() {
                final n = {..._s.typeFilters}; on ? n.add(type) : n.remove(type);
                _s = _s.copyWith(typeFilters: n);
              }),
            ),
        ]),
        const SizedBox(height: 20),
        SizedBox(width: double.infinity, child: FilledButton.icon(
          icon: const Icon(Icons.check),
          label: const Text('Apply'),
          onPressed: () => Navigator.pop(context, _s.copyWith(searchQuery: _searchCtrl.text)),
        )),
      ]),
    ),
  );
}
