import 'package:flutter/material.dart';

import '../models/library_sort_mode.dart';

Future<LibrarySortMode?> showLibrarySortSheet(
  BuildContext context, {
  required LibrarySortMode current,
  required List<LibrarySortMode> modes,
}) {
  return showModalBottomSheet<LibrarySortMode>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      final maxHeight = MediaQuery.sizeOf(context).height * 0.75;

      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  '정렬',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ...modes.map(
                (mode) => ListTile(
                  leading: Icon(
                    current == mode
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                  ),
                  title: Text(mode.label),
                  onTap: () => Navigator.pop(context, mode),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      );
    },
  );
}
