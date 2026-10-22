import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Blocks right-click and long-press context menus on child content.
class ProtectedContent extends StatelessWidget {
  const ProtectedContent({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTap: () {},
      onSecondaryTapDown: (_) {},
      onLongPress: () {},
      onLongPressStart: (_) {},
      child: Listener(
        onPointerDown: (event) {
          final isSecondaryMouse = event.kind == PointerDeviceKind.mouse &&
              (event.buttons & kSecondaryMouseButton) != 0;
          if (isSecondaryMouse) {
            // Absorb right-click at pointer level.
          }
        },
        child: child,
      ),
    );
  }
}
