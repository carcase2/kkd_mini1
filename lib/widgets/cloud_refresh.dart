import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../theme/app_theme.dart';

/// 아래로 당겨 클라우드 동기화(새로고침)
class CloudRefresh extends StatelessWidget {
  final Widget child;
  final Color? color;

  const CloudRefresh({
    super.key,
    required this.child,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return RefreshIndicator(
      color: color ?? c.fasting,
      backgroundColor: c.surface,
      displacement: 48,
      onRefresh: () => context.read<AppState>().refreshFromCloud(),
      child: child,
    );
  }
}
