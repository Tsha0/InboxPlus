import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'network_badge.dart';

class PersonAvatar extends StatelessWidget {
  const PersonAvatar({
    super.key,
    required this.name,
    this.bytes,
    this.network,
    this.isGroup = false,
    this.size = 40,
  });

  final String name;
  final Uint8List? bytes;
  final String? network;
  final bool isGroup;
  final double size;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: isGroup
            ? Icon(Icons.group_outlined, size: size * .5)
            : Text(
                name.characters.firstOrNull?.toUpperCase() ?? '?',
                style: TextStyle(fontSize: size * .45),
              ),
      ),
    );
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: ClipOval(
                child: bytes == null || bytes!.isEmpty
                    ? placeholder
                    : Image.memory(
                        bytes!,
                        fit: BoxFit.cover,
                        cacheWidth:
                            (size * MediaQuery.devicePixelRatioOf(context))
                                .ceil(),
                        frameBuilder: (_, child, frame, _) =>
                            frame == null ? placeholder : child,
                        errorBuilder: (_, _, _) => placeholder,
                      ),
              ),
            ),
            if (network != null)
              Positioned(
                right: -2,
                bottom: -2,
                child: NetworkBadge(
                  network: network,
                  size: size * .4,
                  labelled: false,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
