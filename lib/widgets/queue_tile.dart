import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/pkg_info.dart';
import '../util/format.dart';

/// One package of the send queue, with its progress bar and drag handle.
class QueueTile extends StatelessWidget {
  const QueueTile({
    super.key,
    required this.pkg,
    required this.index,
    required this.served,
    required this.sending,
    required this.viaServer,
    required this.ar,
    required this.onRemove,
  });

  final PkgInfo pkg;
  final int index;
  final int served;
  final bool sending;
  final bool viaServer;
  final bool ar;
  final VoidCallback onRemove;

  String t(String en, String arText) => ar ? arText : en;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final showBar = (sending || served > 0) && viaServer;
    return Card(
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          ListTile(
            leading: pkg.icon == null
                ? const Icon(Icons.inventory_2, size: 40)
                : ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(pkg.icon!, width: 48, height: 48),
                  ),
            title: Text(pkg.title),
            subtitle: Text(
                '${pkg.contentId}\n${pkg.bgftType} · ${fmtSize(pkg.size)}'),
            isThreeLine: true,
            trailing: sending
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: onRemove,
                      ),
                      ReorderableDragStartListener(
                        index: index,
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.drag_handle),
                        ),
                      ),
                    ],
                  ),
          ),
          if (!pkg.isLocal && !pkg.rangeOk)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  '⚠ ${t('No resume support on this server (no fast mode)', 'السيرفر لا يدعم الاستئناف (بدون الوضع السريع)')}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          if (showBar)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: LinearProgressIndicator(
                value: pkg.size == 0 ? 0 : math.min(served, pkg.size) / pkg.size,
              ),
            ),
        ],
      ),
    );
  }
}
