// Grouping of file entries by date for gallery display.
class DateGroup {
  final String label;      // e.g. "Today", "15 May 2025", "April 2025"
  final DateTime date;     // canonical date for this group (midnight)
  final List<Map<String, dynamic>> files;
  DateGroup({required this.label, required this.date, required this.files});
}

class DateGroupModel {
  // Returns the best available date for a file: EXIF taken_at (preferred) or upload created.
  static DateTime _fileDate(Map<String, dynamic> f) {
    final takenRaw = f['taken_at'] as String?;
    if (takenRaw != null) {
      final t = DateTime.tryParse(takenRaw);
      if (t != null) return t.toLocal();
    }
    final createdRaw = f['created'] as String?;
    if (createdRaw != null) {
      final t = DateTime.tryParse(createdRaw);
      if (t != null) return t.toLocal();
    }
    return DateTime.now();
  }

  // Groups files by date (day granularity). Uses EXIF taken_at when available, falls back to created.
  static List<DateGroup> group(List<Map<String, dynamic>> files) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final Map<DateTime, List<Map<String, dynamic>>> buckets = {};
    for (final f in files) {
      final dt = _fileDate(f);
      final key = DateTime(dt.year, dt.month, dt.day);
      buckets.putIfAbsent(key, () => []).add(f);
    }

    final sorted = buckets.keys.toList()..sort((a, b) => b.compareTo(a));
    return sorted.map((key) {
      String label;
      if (key == today) {
        label = 'Today';
      } else if (key == yesterday) {
        label = 'Yesterday';
      } else if (key.year == today.year) {
        label = _fmtDay(key); // "15 May"
      } else {
        label = _fmtDayYear(key); // "15 May 2024"
      }
      return DateGroup(label: label, date: key, files: buckets[key]!);
    }).toList();
  }

  // Groups by month (for scrubbar display). Uses EXIF taken_at when available.
  static List<DateGroup> groupByMonth(List<Map<String, dynamic>> files) {
    final Map<DateTime, List<Map<String, dynamic>>> buckets = {};
    for (final f in files) {
      final dt = _fileDate(f);
      final key = DateTime(dt.year, dt.month);
      buckets.putIfAbsent(key, () => []).add(f);
    }
    final sorted = buckets.keys.toList()..sort((a, b) => b.compareTo(a));
    return sorted.map((key) => DateGroup(
      label: _fmtMonth(key),
      date: key,
      files: buckets[key]!,
    )).toList();
  }

  static String _fmtDay(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${months[d.month - 1]}';
  }

  static String _fmtDayYear(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  static String _fmtMonth(DateTime d) {
    const months = ['January','February','March','April','May','June',
                    'July','August','September','October','November','December'];
    return '${months[d.month - 1]} ${d.year}';
  }
}
