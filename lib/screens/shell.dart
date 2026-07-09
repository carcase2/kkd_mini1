import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/session.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';
import 'masturbation_screen.dart';
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
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final pages = [
      HomeScreen(onNavigate: _goTo),
      const TrackingScreen(type: SessionType.fasting),
      const TrackingScreen(type: SessionType.abstinence),
      const MasturbationScreen(),
      const StatsScreen(),
    ];

    return Scaffold(
      backgroundColor: c.bg,
      body: IndexedStack(
        index: _index,
        children: pages,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: c.navBar,
          border: Border(top: BorderSide(color: c.border.withValues(alpha: 0.8))),
          boxShadow: [
            BoxShadow(
              color: c.shadow,
              blurRadius: 16,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _goTo,
          backgroundColor: Colors.transparent,
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          indicatorColor: c.fasting.withValues(alpha: 0.12),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          height: 68,
          destinations: [
            NavigationDestination(
              icon: Icon(Icons.home_outlined, color: c.textMuted),
              selectedIcon: Icon(Icons.home_rounded, color: c.fasting),
              label: '홈',
            ),
            NavigationDestination(
              icon: Icon(Icons.restaurant_outlined, color: c.textMuted),
              selectedIcon: Icon(Icons.restaurant_rounded, color: c.fasting),
              label: '단식',
            ),
            NavigationDestination(
              icon: Icon(Icons.shield_outlined, color: c.textMuted),
              selectedIcon: Icon(Icons.shield_rounded, color: c.abstinence),
              label: '금욕',
            ),
            NavigationDestination(
              icon: Icon(Icons.favorite_border_rounded, color: c.textMuted),
              selectedIcon: Icon(Icons.favorite_rounded, color: c.check),
              label: '체크',
            ),
            NavigationDestination(
              icon: Icon(Icons.insights_outlined, color: c.textMuted),
              selectedIcon: Icon(Icons.insights_rounded, color: c.success),
              label: '통계',
            ),
          ],
        ),
      ),
    );
  }
}
