import 'package:flutter/material.dart';

import '../util/format.dart';

/// Overall progress of a transfer: percentage, size, speed and time left.
class ProgressCard extends StatelessWidget {
  const ProgressCard({
    super.key,
    required this.total,
    required this.done,
    required this.speed,
    required this.eta,
    required this.ar,
  });

  final int total;
  final int done;
  final double speed;
  final Duration? eta;
  final bool ar;

  String t(String en, String arText) => ar ? arText : en;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (total == 0) {
      return Card(
        color: cs.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(t(
              'The PS4 downloads directly from the links, so no progress is available here.',
              'الـ PS4 يحمّل مباشرة من الروابط، لذلك لا يمكن عرض النسبة هنا.')),
        ),
      );
    }
    final frac = done / total;
    final String etaText;
    if (done >= total) {
      etaText = t('Transfer complete', 'اكتمل النقل');
    } else if (eta == null) {
      etaText = t('Calculating time left…', 'جارٍ حساب الوقت المتبقي…');
    } else {
      etaText = fmtEta(eta!, ar);
    }
    return Card(
      color: cs.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${(frac * 100).toStringAsFixed(1)}%',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: frac,
              minHeight: 8,
              borderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(height: 8),
            Text('${fmtSize(done)} / ${fmtSize(total)}'),
            if (speed > 0)
              Text('${t('Speed', 'السرعة')}: ${fmtSize(speed.round())}/s'),
            const SizedBox(height: 4),
            Text(etaText, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
