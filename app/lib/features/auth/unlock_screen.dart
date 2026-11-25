import 'dart:math' as math;

import 'package:homemade/design/app_logo.dart';
import 'package:homemade/design/content_column.dart';
import 'package:homemade/theme/app_button_styles.dart';
import 'package:homemade/theme/dimens.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

/// Text of the main button of A1.
const unlockLabel = 'Sblocca';

/// Text of the button that leaves the account from A1.
const unlockSignOutLabel = "Esci dall'account";

/// Unlock (A1, `docs/spec/accesso.md`, section 2): logo, name of the app,
/// "Sblocca per continuare"; at the bottom "Sblocca", which asks the system
/// again, and "Esci dall'account".
///
/// It only draws: the unlock shield decides when it shows and what the
/// buttons do. [unlocking] disables "Sblocca" while the request of the
/// system is open.
class UnlockScreen extends StatelessWidget {
  const new({
    required this.onUnlock,
    required this.onSignOut,
    this.unlocking = false,
    super.key,
  });

  /// Share of the height of the screen above the logo: 200 dp on a phone
  /// 844 dp high, about a quarter.
  static const double topShare = 200 / 844;

  /// Least room between the status bar and the logo, on short screens.
  static const double minTopSpace = 48;

  /// Size of the logo.
  static const double logoSize = 88;

  /// Height of "Sblocca".
  static const double unlockButtonHeight = 56;

  /// Icon of "Esci dall'account".
  static const double signOutIconSize = 18;

  /// Room between the buttons and above the gesture bar.
  static const double _buttonGap = AppSpacing.xs;
  static const double _bottomMargin = AppSpacing.xl;

  /// Part of the touch target of "Esci dall'account" (48) around its pill
  /// (44), on each side: it falls in the room above and below.
  static const double _touchSlack =
      (AppSizes.minTouchTarget - AppSizes.compactButtonHeight) / 2;

  final VoidCallback onUnlock;
  final VoidCallback onSignOut;
  final bool unlocking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final buttonStyles = context.buttonStyles;
    final insets = MediaQuery.paddingOf(context);
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final top = math.max(
            constraints.maxHeight * topShare,
            insets.top + minTopSpace,
          );
          return CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.screenMargin + insets.left,
                    top,
                    AppSpacing.screenMargin + insets.right,
                    insets.bottom + _bottomMargin - _touchSlack,
                  ),
                  child: ContentColumn(
                    child: Column(
                      children: [
                        const AppLogo(size: logoSize),
                        const SizedBox(height: AppSpacing.md),
                        Semantics(
                          header: true,
                          child: Text(
                            'Home-made',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineMedium,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'Sblocca per continuare',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        const SizedBox(height: AppSpacing.sectionGap),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: const ButtonStyle(
                              minimumSize: WidgetStatePropertyAll(
                                Size.fromHeight(unlockButtonHeight),
                              ),
                            ),
                            onPressed: unlocking ? null : onUnlock,
                            icon: const Icon(Symbols.fingerprint_rounded),
                            label: const Text(unlockLabel),
                          ),
                        ),
                        const SizedBox(height: _buttonGap - _touchSlack),
                        OutlinedButton.icon(
                          style: buttonStyles.destructive.merge(
                            buttonStyles.compact,
                          ),
                          onPressed: onSignOut,
                          icon: const Icon(
                            Symbols.logout_rounded,
                            size: signOutIconSize,
                          ),
                          label: const Text(unlockSignOutLabel),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
