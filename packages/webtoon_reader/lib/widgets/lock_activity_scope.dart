import 'package:flutter/material.dart';

import '../services/lock_service.dart';

/// 터치·스크롤 등 사용자 활동을 감지해 자동 잠금 타이머를 갱신합니다.
class LockActivityScope extends StatelessWidget {
  const LockActivityScope({super.key, required this.child});

  final Widget child;

  void _touch() => LockService.instance.recordActivity();

  @override
  Widget build(BuildContext context) {
    return NotificationListener<Notification>(
      onNotification: (notification) {
        if (notification is ScrollNotification ||
            notification is UserScrollNotification) {
          _touch();
        }
        return false;
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _touch(),
        onPointerSignal: (_) => _touch(),
        child: child,
      ),
    );
  }
}

/// WebView 등 플랫폼 뷰 안에서의 활동을 타이머에 반영합니다.
void recordLockActivity() => LockService.instance.recordActivity();
