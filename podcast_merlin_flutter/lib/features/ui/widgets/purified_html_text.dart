import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/utils/html_purifier.dart';

class PurifiedHtmlText extends StatelessWidget {
  final String htmlData;
  final TextStyle? textStyle;

  const PurifiedHtmlText({
    super.key,
    required this.htmlData,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    final purified = HtmlPurifier.purify(htmlData);
    if (purified.isEmpty) {
      return const SizedBox.shrink();
    }

    return HtmlWidget(
      purified,
      textStyle: textStyle,
      onTapUrl: (url) async {
        final uri = Uri.tryParse(url);
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri);
          return true;
        }
        return false;
      },
    );
  }
}
