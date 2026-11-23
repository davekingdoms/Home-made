import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:url_launcher/url_launcher.dart';

part 'link_opener.g.dart';

/// Opens a web page outside the app.
typedef LinkOpener = Future<void> Function(Uri uri);

/// Opens [uri] in the browser of the system. It never throws: when no
/// browser takes the link, only the failure is logged, never the address.
Future<void> openInBrowser(Uri uri) async {
  try {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) developer.log('open link failed: not opened', name: 'links');
  } on PlatformException catch (error) {
    developer.log('open link failed: ${error.code}', name: 'links');
  }
}

/// How the app opens web pages; tests override it.
@Riverpod(keepAlive: true)
LinkOpener linkOpener(Ref ref) => openInBrowser;
