import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/app_state.dart';
import 'services/updater.dart';
import 'util/brand.dart';
import 'util/legal.dart';

/// About: version, disclaimer, privacy, license, credits and support links.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const _source = 'https://github.com/$kRepo';
  static const _issues = 'https://github.com/$kRepo/issues';

  Future<void> _copy(BuildContext context, String text, String done) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(done)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: appArabic,
      builder: (context, ar, _) {
        String t(String en, String arText) => ar ? arText : en;
        final cs = Theme.of(context).colorScheme;
        final version = kBuildNumber == 0 ? t('development build', 'نسخة تطوير') : 'v1.0.$kBuildNumber';

        Widget section(String title, String body) => Card(
              color: cs.surfaceContainerHigh,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                title: Text(title, style: Theme.of(context).textTheme.titleSmall),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [Text(body)],
              ),
            );

        return Directionality(
          textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            appBar: AppBar(title: Text(t('About', 'حول التطبيق'))),
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Center(
                    child: Column(children: [
                      Icon(Icons.send_rounded, size: 56, color: cs.primary),
                      const SizedBox(height: 8),
                      Text(kAppName, style: Theme.of(context).textTheme.headlineSmall),
                      Text(version, style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 8),
                      Text(
                        t('Send PKG links and files to a console running GoldHEN.',
                            'أرسل روابط وملفات PKG إلى جهاز يعمل عليه GoldHEN.'),
                        textAlign: TextAlign.center,
                      ),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  section(t('Disclaimer', 'إخلاء المسؤولية'), disclaimerText(ar)),
                  section(t('Privacy policy', 'سياسة الخصوصية'), privacyText(ar)),
                  section(
                    t('License and source code', 'الرخصة والكود المصدري'),
                    t('This app is free software under the GNU GPL v3. You may use, study, change and share it under the same license. The source code is available at the link below.',
                        'هذا التطبيق برنامج حر بموجب رخصة GNU GPL v3. يمكنك استخدامه ودراسته وتعديله ومشاركته بنفس الرخصة. الكود المصدري متاح في الرابط أدناه.'),
                  ),
                  section(t('Credits', 'الشكر والمصادر'), creditsText(ar)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _copy(context, _source,
                            t('Source link copied.', 'تم نسخ رابط الكود المصدري.')),
                        icon: const Icon(Icons.code),
                        label: Text(t('Copy source link', 'نسخ رابط الكود')),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _copy(context, _issues,
                            t('Support link copied.', 'تم نسخ رابط الدعم.')),
                        icon: const Icon(Icons.bug_report_outlined),
                        label: Text(t('Report a problem', 'الإبلاغ عن مشكلة')),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => showLicensePage(
                          context: context,
                          applicationName: kAppName,
                          applicationVersion: version,
                          applicationLegalese: 'GNU GPL v3',
                        ),
                        icon: const Icon(Icons.description_outlined),
                        label: Text(t('Library licenses', 'تراخيص المكتبات')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
