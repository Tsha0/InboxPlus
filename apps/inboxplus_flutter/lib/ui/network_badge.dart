import 'package:flutter/material.dart';

import 'platform_glyphs.dart';

const networkNames = {
  'whatsapp': 'WhatsApp',
  'telegram': 'Telegram',
  'instagram': 'Instagram',
  'messenger': 'Facebook Messenger',
  'imessage': 'iMessage',
  'discord': 'Discord',
  'matrix': 'Matrix',
  'linkedIn': 'LinkedIn',
  'slack': 'Slack',
  'x': 'X',
};

class NetworkBadge extends StatelessWidget {
  const NetworkBadge({
    super.key,
    required this.network,
    this.size = 22,
    this.labelled = true,
  });

  final String? network;
  final double size;
  final bool labelled;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final badge = Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * .22),
      decoration: BoxDecoration(
        color: dark ? Colors.white : Colors.black,
        borderRadius: BorderRadius.circular(size * .25),
      ),
      child: CustomPaint(
        painter: _GlyphPainter(
          network ?? '',
          dark ? Colors.black : Colors.white,
        ),
      ),
    );
    return labelled
        ? Semantics(label: networkNames[network] ?? network, child: badge)
        : ExcludeSemantics(child: badge);
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.network, this.color);
  final String network;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = platformGlyphPath(network);
    if (path == null) return;
    canvas.scale(size.width / 24, size.height / 24);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      network != old.network || color != old.color;
}
