import 'package:flutter/material.dart';

import '../services/lock_service.dart';

class LockButton extends StatelessWidget {
  const LockButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => LockService.instance.lock(force: true),
      icon: const Icon(Icons.lock_outline),
      tooltip: '잠금',
    );
  }
}
