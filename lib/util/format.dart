/// Human readable size, e.g. "55.75 MB".
String fmtSize(int b) {
  const u = ['B', 'KB', 'MB', 'GB'];
  var v = b.toDouble();
  var i = 0;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(i == 0 ? 0 : 2)} ${u[i]}';
}

/// "About 12 min left" in the chosen language.
String fmtEta(Duration d, bool ar) {
  String t(String en, String arText) => ar ? arText : en;
  if (d.inSeconds < 60) {
    return t('Less than a minute left', 'متبقي أقل من دقيقة');
  }
  final m = (d.inSeconds / 60).ceil();
  if (m < 60) return t('About $m min left', 'متبقي حوالي $m دقيقة');
  final h = m ~/ 60;
  final mm = m % 60;
  return t('About $h h $mm min left', 'متبقي حوالي $h ساعة و$mm دقيقة');
}
