import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:homemade/core/router/app_router.dart';
import 'package:homemade/theme/app_theme.dart';
import 'package:homemade/theme/appearance.dart';
import 'package:homemade/theme/text_scale.dart';
import 'package:material_ui/material_ui.dart';

class HomemadeApp extends ConsumerWidget {
  const new({super.key});

  /// The app is in Italian only.
  static const locale = Locale('it');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceControllerProvider);
    return MaterialApp.router(
      title: 'Home-made',
      theme: buildAppTheme(appearance.palette, Brightness.light),
      darkTheme: buildAppTheme(appearance.palette, Brightness.dark),
      themeMode: appearance.themeMode,
      locale: locale,
      supportedLocales: const [locale],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(appRouterProvider),
      builder: (context, child) => AppTextScale.clamp(child: child!),
    );
  }
}
