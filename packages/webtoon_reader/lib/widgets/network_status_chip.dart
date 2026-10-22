import 'package:flutter/material.dart';

import '../services/connectivity_service.dart';

class NetworkStatusChip extends StatelessWidget {
  const NetworkStatusChip({super.key, this.compact = false, this.light = false});

  final bool compact;
  final bool light;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ConnectivityService.instance,
      builder: (context, _) {
        final net = ConnectivityService.instance;
        final online = net.isOnline;
        final scheme = Theme.of(context).colorScheme;
        final fg = light
            ? Colors.white
            : online
                ? scheme.primary
                : scheme.onSurfaceVariant;
        final bg = light
            ? Colors.white.withValues(alpha: 0.14)
            : online
                ? scheme.primaryContainer.withValues(alpha: 0.7)
                : scheme.surfaceContainerHighest;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                final messenger = ScaffoldMessenger.maybeOf(context);
                messenger?.hideCurrentSnackBar();
                messenger?.showSnackBar(
                  SnackBar(content: Text(net.detailLabel)),
                );
              },
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 8 : 10,
                  vertical: compact ? 4 : 6,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      online
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_off_outlined,
                      size: 15,
                      color: fg,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      net.statusLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: fg,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ConnectivityService.instance,
      builder: (context, _) {
        if (ConnectivityService.instance.isOnline) {
          return const SizedBox.shrink();
        }
        final scheme = Theme.of(context).colorScheme;
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(Icons.cloud_off_outlined, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '오프라인 · 기기에 저장된 만화만 볼 수 있습니다',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
