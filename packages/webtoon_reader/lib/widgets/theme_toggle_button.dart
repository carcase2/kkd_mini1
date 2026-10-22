import 'package:flutter/material.dart';

import '../services/theme_mode_service.dart';

/// 앱바용 라이트/다크 전환 버튼.
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeModeService.instance,
      builder: (context, _) {
        final isDark = ThemeModeService.instance.isDark;
        return IconButton(
          tooltip: isDark ? '라이트 모드' : '다크 모드',
          onPressed: () {
            ThemeModeService.instance.toggleLightDark();
          },
          icon: Icon(
            isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          ),
        );
      },
    );
  }
}
