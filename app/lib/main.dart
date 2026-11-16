import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:homemade/app.dart';
import 'package:homemade/theme/font_license.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  registerFontLicense();
  runApp(const ProviderScope(child: HomemadeApp()));
}
