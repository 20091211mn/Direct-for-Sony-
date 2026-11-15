import 'dart:math' as math;

import 'package:flutter/services.dart';

/// Keeps only digits and dots. The iPhone number pad has no "." key (or shows
/// a locale separator), so ",", "٫", "،" become "." and Arabic digits become 0-9.
class IpFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final src = newValue.text;
    final sel = newValue.selection.baseOffset;
    final out = StringBuffer();
    var cursor = 0;
    for (var i = 0; i < src.length; i++) {
      if (i == sel) cursor = out.length;
      final c = src.codeUnitAt(i);
      if (c >= 0x30 && c <= 0x39) {
        out.writeCharCode(c);
      } else if (c >= 0x0660 && c <= 0x0669) {
        out.writeCharCode(0x30 + c - 0x0660);
      } else if (c >= 0x06F0 && c <= 0x06F9) {
        out.writeCharCode(0x30 + c - 0x06F0);
      } else if (c == 0x2E ||
          c == 0x2C ||
          c == 0x066B ||
          c == 0x060C ||
          c == 0x3002 ||
          c == 0xFF0C) {
        out.write('.');
      }
    }
    if (sel < 0 || sel >= src.length) cursor = out.length;
    final text = out.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: math.min(cursor, text.length)),
    );
  }
}
