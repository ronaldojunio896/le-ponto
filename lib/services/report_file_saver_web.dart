// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

Future<String> saveReportBytes({
  required String name,
  required List<int> bytes,
  required String mimeType,
}) async {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  try {
    html.AnchorElement(href: url)
      ..download = name
      ..click();
  } finally {
    html.Url.revokeObjectUrl(url);
  }
  return name;
}
