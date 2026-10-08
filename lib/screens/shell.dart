import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/session.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import 'habit_screen.dart';
import 'home_screen.dart';
import 'masturbation_screen.dart';
import 'medication_screen.dart';
import 'reading_screen.dart';
import 'stats_screen.dart';
import 'tracking_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      context.read<AppState>().tick();
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }

  void _goTo(int index) {
    if (index == _index) return;
    HapticFeedback.selectionClick();
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final pages = [
      HomeScreen(onNavigate: _goTo),
      const TrackingScreen(type: SessionType.fasting),
      const TrackingScreen(type: SessionType.abstinence),
      const ReadingScreen(),
      const MasturbationScreen(),
      const HabitScreen(),
      const MedicationScreen(),
      const StatsScreen(),
    ];

    return Scaffold(
      backgroundColor: c.bg,
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: _TabBar(index: _index, colors: c, onSelected: _goTo),
    );
  }
}

class _TabSpec {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final Color color;

  const _TabSpec({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.color,
  });
}

/// 여덟 개 탭의 이름과 색을 항상 보여 주는 하단 바.
class _TabBar extends StatelessWidget {
  final int index;
  final AppPalette colors;
  final ValueChanged<int> onSelected;

  const _TabBar({
    required this.index,
    required this.colors,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final tabs = [
      _TabSpec(
        icon: Icons.home_outlined,
        selectedIcon: Icons.home_rounded,
        label: '홈',
        color: c.fasting,
      ),
      _TabSpec(
        icon: Icons.restaurant_outlined,
        selectedIcon: Icons.restaurant_rounded,
        label: '단식',
        color: c.fasting,
      ),
      _TabSpec(
        icon: Icons.shield_outlined,
        selectedIcon: Icons.shield_rounded,
        label: '금욕',
        color: c.abstinence,
      ),
      _TabSpec(
        icon: Icons.menu_book_outlined,
        selectedIcon: Icons.menu_book_rounded,
        label: '독서',
        color: c.reading,
      ),
      _TabSpec(
        icon: Icons.favorite_border_rounded,
        selectedIcon: Icons.favorite_rounded,
        label: '체크',
        color: c.check,
      ),
      _TabSpec(
        icon: Icons.checklist_outlined,
        selectedIcon: Icons.checklist_rounded,
        label: '습관',
        color: c.habit,
      ),
      _TabSpec(
        icon: Icons.medication_outlined,
        selectedIcon: Icons.medication_rounded,
        label: '약',
        color: c.warning,
      ),
      _TabSpec(
        icon: Icons.insights_outlined,
        selectedIcon: Icons.insights_rounded,
        label: '통계',
        color: c.success,
      ),
    ];

    return Material(
      color: c.navBar,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: c.border.withValues(alpha: 0.9)),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 2),
            child: Row(
              children: [
                for (var i = 0; i < tabs.length; i++)
                  Expanded(
                    child: _TabButton(
                      spec: tabs[i],
                      selected: i == index,
                      muted: c.textMuted,
                      onTap: () => onSelected(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final _TabSpec spec;
  final bool selected;
  final Color muted;
  final VoidCallback onTap;

  const _TabButton({
    required this.spec,
    required this.selected,
    required this.muted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? spec.color : muted;
    return Semantics(
      button: true,
      selected: selected,
      label: spec.label,
      child: InkWell(
        onTap: onTap,
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  width: 32,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? spec.color.withValues(alpha: 0.16)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    selected ? spec.selectedIcon : spec.icon,
                    size: 20,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  spec.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.05,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
