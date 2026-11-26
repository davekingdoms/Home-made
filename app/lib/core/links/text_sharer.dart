import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:share_plus/share_plus.dart';

part 'text_sharer.g.dart';

/// Hands a text to the share sheet of the system.
typedef TextSharer = Future<void> Function(String text);

/// Opens the share sheet of the system with [text]. It never throws: a
/// failure is logged with its code only, never the text.
Future<void> shareWithSystem(String text) async {
  try {
    await SharePlus.instance.share(ShareParams(text: text));
  } on PlatformException catch (error) {
    developer.log('share failed: ${error.code}', name: 'links');
  }
}

/// How the app shares a text; tests override it.
@Riverpod(keepAlive: true)
TextSharer textSharer(Ref ref) => shareWithSystem;
