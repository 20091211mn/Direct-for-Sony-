/// Disclaimer, privacy policy and credits shown in the app (Arabic / English).
/// Keep PRIVACY.md and DISCLAIMER.md in the repository in sync with these texts.

String disclaimerText(bool ar) => ar
    ? '''• هذا مشروع مستقل وغير مرتبط بشركة Sony Interactive Entertainment ولا تدعمه. "PlayStation" و"PS4" علامات تجارية لأصحابها.
• التطبيق مخصّص لبرامج homebrew ولنسخ احتياطية من برامج تملكها بشكل قانوني. لا تستخدمه لتثبيت محتوى مقرصَن.
• يحتاج التطبيق إلى جهاز عدّلته أنت مسبقاً (GoldHEN). تعديل الجهاز قد يخالف شروط الاستخدام أو الضمان وقد يعرّض حسابك للحظر. استخدمه على مسؤوليتك.
• كتالوج المتجر يديره المشرف، والملفات قد تكون مستضافة لدى أطراف ثالثة. المطوّر غير مسؤول عن محتواها.
• التطبيق مقدَّم "كما هو" بدون أي ضمان، بموجب رخصة GPL-3.0.
• لطلبات إزالة محتوى أو الإبلاغ عن مخالفة، افتح بلاغاً في صفحة المشروع على GitHub.'''
    : '''• This is an independent project, not affiliated with or endorsed by Sony Interactive Entertainment. "PlayStation" and "PS4" are trademarks of their owners.
• The app is meant for homebrew software and backups of software you legally own. Do not use it to install pirated content.
• It needs a console that you already modified (GoldHEN). Modifying a console may violate its terms of use or warranty and may risk a ban. Use it at your own risk.
• The store catalog is curated by its admin and files may be hosted by third parties. The developer is not responsible for their content.
• The app is provided "as is", without any warranty, under the GPL-3.0 license.
• To request the removal of content or report a violation, open an issue on the project's GitHub page.''';

String privacyText(bool ar) => ar
    ? '''لا يجمع التطبيق بياناتك. لا توجد حسابات ولا إعلانات ولا تحليلات ولا تقارير أعطال.

ما يُحفظ على جهازك فقط: عنوان الـ PS4، سجل الروابط الأخيرة، اللغة والإعدادات، نسخة من الكتالوج والإشعارات، وأي إصدارات من المتجر أرسلتها. تُحذف بحذف التطبيق أو مسح بياناته.

الاتصالات بالإنترنت:
• GitHub (api.github.com وraw.githubusercontent.com وgithub.com): للتحقق من التحديثات وقراءة المتجر والإشعارات. يرى GitHub عنوان الـ IP الخاص بك.
• الروابط التي تضيفها أنت: يرى السيرفر صاحب الرابط عنوان الـ IP الخاص بك عند التحميل.
• الشبكة المحلية: الاتصال بالـ PS4 لديك، وهو يتصل بجوالك لسحب الملف. لا يخرج شيء من شبكتك المحلية عدا ما ذُكر.

صلاحيات أندرويد: الإنترنت، تشغيل خدمة في الخلفية وإبقاء الجهاز مستيقظاً أثناء النقل، الإشعارات، تثبيت التحديثات (عند تحديث التطبيق فقط)، وإعادة جدولة الفحص بعد إعادة التشغيل.

تطبيق الإدارة يحفظ توكن GitHub على جهازك فقط ولا يرسله لأي جهة غير GitHub.'''
    : '''The app does not collect your data. There are no accounts, ads, analytics or crash reports.

Only stored on your device: the PS4 address, recent links, language and settings, a copy of the catalog and notices, and the store versions you sent. Uninstalling the app or clearing its data removes them.

Internet connections:
• GitHub (api.github.com, raw.githubusercontent.com, github.com): to check for updates and read the store and notices. GitHub sees your IP address.
• Links you add yourself: the server of that link sees your IP address when downloading.
• Local network: the connection to your PS4, which connects back to your phone to fetch the file. Nothing leaves your local network except what is listed above.

Android permissions: internet, a background service and keeping the device awake during transfers, notifications, installing updates (only when updating the app), and rescheduling the check after a restart.

The admin app stores a GitHub token on your device only and sends it to no one except GitHub.''';

String creditsText(bool ar) => ar
    ? '''مبني على DirectPackageInstaller للمطوّر marcussacana (رخصة GPL-3.0). ملف الـ payload مأخوذ من ذلك المشروع (قالب الـ payload من sleirsgoevy، وصادرات PS4 من OpenOrbis SDK).
قراءة ترويسة PKG مبنية على توثيق مكتبة LibOrbisPkg.'''
    : '''Based on DirectPackageInstaller by marcussacana (GPL-3.0). The payload comes from that project (payload template by sleirsgoevy, PS4 exports by the OpenOrbis SDK).
PKG header parsing follows the LibOrbisPkg documentation.''';
