import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:homemade/core/router/app_router.dart';
import 'package:homemade/theme/app_theme.dart';
import 'package:homemade/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

class HomemadeApp extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Home-made',
      theme: buildAppTheme(AppPalette.teal, Brightness.light),
      darkTheme: buildAppTheme(AppPalette.teal, Brightness.dark),
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
