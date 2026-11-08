import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const quickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

Future<String?> showReactionPicker(
  BuildContext context, {
  required Set<String> ownReactions,
  Offset? anchor,
}) => showDialog<String>(
  context: context,
  barrierColor: Colors.transparent,
  builder: (context) => Padding(
    padding: MediaQuery.viewInsetsOf(context),
    child: CustomSingleChildLayout(
      delegate: _PickerPosition(anchor),
      child: Material(
        elevation: 6,
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: ReactionPicker(
          ownReactions: ownReactions,
          onSelected: (emoji) => Navigator.pop(context, emoji),
        ),
      ),
    ),
  ),
);

class _PickerPosition extends SingleChildLayoutDelegate {
  _PickerPosition(this.anchor);

  final Offset? anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: math.min(252, math.max(0, constraints.maxWidth - 16)),
        maxHeight: math.max(0, constraints.maxHeight - 16),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    if (anchor == null) {
      return Offset(
        (size.width - childSize.width) / 2,
        (size.height - childSize.height) / 2,
      );
    }
    final position = anchor!;
    return Offset(
      position.dx.clamp(8, math.max(8, size.width - childSize.width - 8)),
      (position.dy + 8).clamp(
        8,
        math.max(8, size.height - childSize.height - 8),
      ),
    );
  }

  @override
  bool shouldRelayout(_PickerPosition oldDelegate) =>
      anchor != oldDelegate.anchor;
}

class ReactionPicker extends StatefulWidget {
  const ReactionPicker({
    super.key,
    required this.ownReactions,
    required this.onSelected,
  });

  final Set<String> ownReactions;
  final ValueChanged<String> onSelected;

  @override
  State<ReactionPicker> createState() => _ReactionPickerState();
}

class _ReactionPickerState extends State<ReactionPicker> {
  final _catalog = rootBundle
      .loadString('assets/reaction_emoji.json')
      .then((value) => jsonDecode(value) as Map<String, dynamic>);
  bool _expanded = false;
  final _searchFocus = FocusNode();
  final _search = TextEditingController();
  List<String> _results = [];

  @override
  void dispose() {
    _searchFocus.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Reaction picker',
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: SizedBox(
          width: 236,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final emoji in quickReactions) _emoji(emoji),
                  Semantics(
                    label: _expanded ? 'Fewer emoji' : 'More emoji',
                    button: true,
                    excludeSemantics: true,
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: SizedBox.square(
                      dimension: 32,
                      child: IconButton(
                        tooltip: _expanded ? 'Fewer emoji' : 'More emoji',
                        padding: EdgeInsets.zero,
                        style: IconButton.styleFrom(
                          backgroundColor: scheme.onSurface.withValues(
                            alpha: .08,
                          ),
                        ),
                        icon: Icon(
                          _expanded ? Icons.keyboard_arrow_up : Icons.add,
                          size: 18,
                        ),
                        onPressed: () => setState(() => _expanded = !_expanded),
                      ),
                    ),
                  ),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 8),
                Semantics(
                  label: 'Search emoji',
                  onTap: _searchFocus.requestFocus,
                  child: TextField(
                    key: const Key('search-reactions'),
                    controller: _search,
                    focusNode: _searchFocus,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Search emoji',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) {
                      if (_results.isNotEmpty) {
                        widget.onSelected(_results.first);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: SizedBox(
                    height: 230,
                    child: FutureBuilder(
                      future: _catalog,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return const Center(
                            child: Text('Could not load emoji'),
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final words = _search.text.toLowerCase().trim().split(
                          RegExp(r'\s+'),
                        );
                        final searching = words.first.isNotEmpty;
                        _results = searching
                            ? [
                                for (final entry
                                    in snapshot.data!['named'] as List)
                                  if (words.every(
                                    (word) => (entry['name'] as String)
                                        .contains(word),
                                  ))
                                    entry['emoji'] as String,
                              ]
                            : [];
                        if (searching && _results.isEmpty) {
                          return const Center(child: Text('No emoji found'));
                        }
                        return CustomScrollView(
                          slivers: [
                            if (searching)
                              _grid(_results)
                            else
                              for (final category
                                  in snapshot.data!['categories'] as List) ...[
                                SliverToBoxAdapter(
                                  child: Semantics(
                                    header: true,
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                        top: 6,
                                        bottom: 4,
                                      ),
                                      child: Text(
                                        category['name'] as String,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                _grid(
                                  (category['emoji'] as List).cast<String>(),
                                ),
                              ],
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _grid(List<String> emoji) => SliverGrid.builder(
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 7,
      mainAxisSpacing: 2,
      crossAxisSpacing: 2,
    ),
    itemCount: emoji.length,
    itemBuilder: (context, index) => _emoji(emoji[index]),
  );

  Widget _emoji(String emoji) {
    final own = widget.ownReactions.contains(emoji);
    final label = own ? 'Remove your $emoji' : 'React with $emoji';
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        button: true,
        selected: own,
        excludeSemantics: true,
        onTap: () => widget.onSelected(emoji),
        child: SizedBox.square(
          dimension: 32,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => widget.onSelected(emoji),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: own
                    ? Theme.of(context).colorScheme.primary
                          .withValues(alpha: .18)
                    : Colors.transparent,
              ),
              child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 21)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
