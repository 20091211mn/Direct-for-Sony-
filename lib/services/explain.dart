import 'dart:async';
import 'dart:io';

import 'pkg_info.dart';

/// Turns a failure into a clear message in the chosen language.
String explainError(Object e, bool ar) {
  String t(String en, String arText) => ar ? arText : en;
  if (e is PkgError) {
    switch (e.code) {
      case 'invalid_url':
        return t('This is not a valid link. It must start with http:// or https://.',
            'هذا ليس رابطاً صالحاً. يجب أن يبدأ بـ http:// أو https://.');
      case 'html_page':
        return t('The link opens a web page, not the PKG file. Use the direct download link.',
            'الرابط يفتح صفحة ويب وليس ملف PKG. استخدم رابط التحميل المباشر.');
      case 'forbidden':
        return t('The server refused access (the link expired or needs a login). Get a fresh link.',
            'السيرفر رفض الوصول (انتهت صلاحية الرابط أو يحتاج تسجيل دخول). احصل على رابط جديد.');
      case 'not_found':
        return t('The file was not found (404). Check the link.',
            'الملف غير موجود (404). تحقق من الرابط.');
      case 'server_error':
        return t('The server returned an error (${e.detail}). Try again later.',
            'السيرفر أرجع خطأ (${e.detail}). حاول لاحقاً.');
      case 'no_size':
        return t('The server did not report the file size, so it cannot be used.',
            'السيرفر لم يرسل حجم الملف، فلا يمكن استخدامه.');
      case 'archive':
        return t('This is a compressed archive (${e.detail}). Extract it and use the .pkg file.',
            'هذا ملف مضغوط (${e.detail}). فك الضغط واستخدم ملف .pkg.');
      case 'not_pkg':
        return t('This is not a PS4 PKG file (${e.detail}).',
            'هذا ليس ملف PS4 PKG (${e.detail}).');
    }
  }
  if (e is SocketException) {
    return t('Cannot reach the server. Check the internet connection and the link.',
        'تعذّر الاتصال بالسيرفر. تحقق من الإنترنت ومن الرابط.');
  }
  if (e is TimeoutException) {
    return t('The connection timed out.', 'انتهت مهلة الاتصال.');
  }
  if (e is TlsException) {
    return t('There is a problem with the HTTPS certificate of this site.',
        'توجد مشكلة في شهادة HTTPS لهذا الموقع.');
  }
  return e.toString();
}

/// Same for failures while sending to the PS4.
String explainSend(Object e, bool ar) {
  String t(String en, String arText) => ar ? arText : en;
  final s = e.toString();
  if (s.contains('Could not reach BinLoader')) {
    return t('Cannot reach the PS4. Enable GoldHEN > Servers > BinLoader and check the IP.',
        'تعذّر الوصول إلى الـ PS4. فعّل GoldHEN > Servers > BinLoader وتحقق من العنوان.');
  }
  if (e is TimeoutException) {
    return t('The PS4 payload did not connect back to the phone. Make sure both are on the same Wi-Fi and that the router does not isolate devices (AP isolation).',
        'الـ payload على الـ PS4 لم يتصل بالجوال. تأكد أنهما على نفس الواي فاي وأن الراوتر لا يعزل الأجهزة (AP isolation).');
  }
  return explainError(e, ar);
}
