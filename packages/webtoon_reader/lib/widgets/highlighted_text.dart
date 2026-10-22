import 'package:flutter/material.dart';

import '../utils/text_search.dart';

class HighlightedText extends StatelessWidget {
  const HighlightedText({
    super.key,
    required this.text,
    this.highlight,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });

  final String text;
  final String? highlight;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    final needle = TextSearch.normalize(highlight ?? '');
    if (needle.isEmpty) {
      return Text(
        text,
        style: baseStyle,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final highlightStyle = baseStyle.copyWith(
      backgroundColor: scheme.primaryContainer.withValues(alpha: 0.95),
      color: scheme.onPrimaryContainer,
      fontWeight: FontWeight.w700,
    );

    final spans = <InlineSpan>[];
    final lower = text.toLowerCase();
    var cursor = 0;
    while (cursor < text.length) {
      final index = lower.indexOf(needle, cursor);
      if (index < 0) {
        spans.add(TextSpan(text: text.substring(cursor), style: baseStyle));
        break;
      }
      if (index > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, index), style: baseStyle));
      }
      final end = index + needle.length;
      spans.add(TextSpan(text: text.substring(index, end), style: highlightStyle));
      cursor = end;
    }

    return Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
      textAlign: textAlign,
    );
  }
}
