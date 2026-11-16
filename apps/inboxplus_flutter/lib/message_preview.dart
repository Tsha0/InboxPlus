class MessagePreviewWindow {
  MessagePreviewWindow({required this.lines, required this.pageSize});

  final List<String> lines;
  final int pageSize;

  List<String> page(int index) {
    if (index < 0 || pageSize <= 0 || lines.isEmpty) return const [];
    final start = index * pageSize;
    if (start >= lines.length) return const [];
    final end = start + pageSize;
    final window = <String>[];
    for (var i = start; i <= end && i < lines.length; i++) {
      window.add(lines[i]);
    }
    return window;
  }

  String headline() => lines[0];

  String snippet(int maxCharacters) {
    if (maxCharacters <= 0) return '';
    final text = joined();
    if (text.length <= maxCharacters) return text;
    return text.substring(0, maxCharacters);
  }

  String joined() {
    final buffer = StringBuffer();
    var first = true;
    for (final line in lines) {
      if (!first) {
        buffer.write('\n');
      }
      buffer.write(line);
      first = false;
    }
    return buffer.toString();
  }
}
