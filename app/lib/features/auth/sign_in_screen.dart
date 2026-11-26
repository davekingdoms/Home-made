import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:homemade/core/config/app_config.dart';
import 'package:homemade/design/app_logo.dart';
import 'package:homemade/design/content_column.dart';
import 'package:homemade/design/highlight_card.dart';
import 'package:homemade/features/auth/auth_repository.dart';
import 'package:homemade/features/startup/startup_gate.dart';
import 'package:homemade/theme/app_colors.dart';
import 'package:homemade/theme/dimens.dart';
import 'package:material_ui/material_ui.dart';

/// Text of A2 after an expired or revoked session.
const sessionLostMessage = 'La sessione è scaduta: accedi di nuovo.';

/// The phrase of the app, in the card of A2.
const appPhrase = 'Conti, spese e conguagli di casa in un posto solo.';

/// Text of the button of A2.
const signInLabel = 'Continua con Google';

/// The line under the button of A2.
const signInCaption = 'Accedi o registrati con il tuo account Google.';

/// The message A2 shows after a sign-in that ended with [result]; null for
/// none.
///
/// `google_sign_in` has no code of its own for a phone without a Google
/// account (on Android it is an `unknownError`, told apart only by its
/// description): that case gets the generic message, and the log only the
/// code.
String? signInMessage(SignInResult result) => switch (result) {
  SignInResult.signedIn || SignInResult.cancelled => null,
  SignInResult.networkError =>
    'Nessuna connessione. Controlla la rete e riprova.',
  SignInResult.configurationError ||
  SignInResult.rejected ||
  SignInResult.failed => 'Accesso non riuscito. Riprova.',
};

/// Text of the checkbox of the demo accounts in A2.
const demoChoiceLabel = 'Modalità demo';

/// Sign-in (A2, `docs/spec/accesso.md`, section 3): at the top the
/// highlighted card with the logo, the name of the app and its phrase; at
/// the bottom "Continua con Google", the one way to sign in and to sign up,
/// with its line. On `dev` only, the checkbox of the demo accounts
/// (section 12). After a lost session, a fixed notice above the button.
class SignInScreen extends ConsumerStatefulWidget {
  const new({super.key});

  /// Height of the card on a phone [phoneHeight] dp high: the card takes the
  /// same share of the height under the status bar on every screen.
  static const double phoneCardHeight = 460;
  static const double phoneHeight = 844;

  /// Least height of the card, on short or landscape screens.
  static const double minCardHeight = 280;

  /// Size of the logo in the card.
  static const double logoSize = 72;

  /// Height of "Continua con Google".
  static const double buttonHeight = 56;

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  bool _signingIn = false;

  /// The choice of "Modalità demo"; null until it is read from the device.
  bool? _demo;

  @override
  void initState() {
    super.initState();
    if (ref.read(appConfigProvider).isDev) unawaited(_readDemoChoice());
  }

  Future<void> _readDemoChoice() async {
    final chosen = await ref.read(startupGateProvider).demoChosen();
    // A tap that came first wins.
    if (mounted && _demo == null) setState(() => _demo = chosen);
  }

  void _chooseDemo(bool demo) {
    setState(() => _demo = demo);
    unawaited(ref.read(startupGateProvider).chooseDemo(demo: demo));
  }

  Future<void> _signIn() async {
    setState(() => _signingIn = true);
    final result = await ref.read(authRepositoryProvider).signInWithGoogle();
    // With a session the router leaves this screen: the indicator stays
    // until then.
    if (!mounted || result == SignInResult.signedIn) return;
    setState(() => _signingIn = false);
    final message = signInMessage(result);
    if (message == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gate = ref.watch(startupGateProvider);
    final insets = MediaQuery.paddingOf(context);
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final cardHeight = math.max(
            (constraints.maxHeight - insets.top) *
                SignInScreen.phoneCardHeight /
                SignInScreen.phoneHeight,
            SignInScreen.minCardHeight,
          );
          return CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding:
                      ContentColumn.sidePadding(
                        constraints.maxWidth,
                        insets,
                      ).copyWith(
                        top: AppSpacing.screenMargin + insets.top,
                        bottom: AppSpacing.xl + insets.bottom,
                      ),
                  child: ContentColumn(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Flexible(
                          child: _ShrinkableHeight(
                            height: cardHeight,
                            minHeight: SignInScreen.minCardHeight,
                            child: const _TitleCard(),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Least room between the card and what follows.
                            const SizedBox(height: AppSpacing.sm),
                            ValueListenableBuilder(
                              valueListenable: gate,
                              builder: (context, state, _) => !state.sessionLost
                                  ? const SizedBox.shrink()
                                  : const Padding(
                                      padding: EdgeInsets.only(
                                        bottom: AppSpacing.sm,
                                      ),
                                      child: _SessionLostNotice(),
                                    ),
                            ),
                            FilledButton(
                              style: const ButtonStyle(
                                minimumSize: WidgetStatePropertyAll(
                                  Size.fromHeight(SignInScreen.buttonHeight),
                                ),
                              ),
                              onPressed: _signingIn
                                  ? null
                                  : () => unawaited(_signIn()),
                              child: _signingIn
                                  ? const SizedBox.square(
                                      dimension: AppSizes.iconSmall,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(signInLabel),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              signInCaption,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: context.appColors.testoTerziario,
                              ),
                            ),
                            if (ref.watch(appConfigProvider).isDev) ...[
                              const SizedBox(height: AppSpacing.xs),
                              _DemoCheckbox(
                                value: _demo ?? false,
                                enabled: !_signingIn,
                                onChanged: _chooseDemo,
                              ),
                            ],
                          ],
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

/// The highlighted card of A2: logo, name of the app and its phrase at the
/// bottom start. It cannot be tapped; the screen reader reads it as one.
class _TitleCard extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return HighlightCard(
      radius: AppRadii.hubCard,
      padding: const EdgeInsets.all(AppSpacing.xl),
      semanticLabel: 'Home-made. $appPhrase',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppLogo(size: SignInScreen.logoSize, onCard: true),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Home-made',
            style: textTheme.displaySmall?.copyWith(
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            appPhrase,
            style: textTheme.bodyLarge?.copyWith(
              color: context.appColors.suPrimarioTenue,
            ),
          ),
        ],
      ),
    );
  }
}

/// The notice of a lost session: a fixed box with the look of a snackbar,
/// above the button until the next sign-in. It is no [SnackBar]: it does not
/// go away and has no action.
class _SessionLostNotice extends StatelessWidget {
  const new();

  /// The padding of the content of a snackbar.
  static const _padding = EdgeInsets.symmetric(
    vertical: 14,
    horizontal: AppSpacing.md,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // The style of the content of the snackbars of the theme.
    final style =
        theme.snackBarTheme.contentTextStyle ??
        theme.textTheme.bodyMedium?.copyWith(color: scheme.onInverseSurface);
    // A polite live region: the role of a status. Flutter does not allow the
    // role itself together with it, and Android reads the live region.
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: AppSizes.minTouchTarget),
        padding: _padding,
        alignment: AlignmentDirectional.centerStart,
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(AppRadii.small),
        ),
        child: Text(sessionLostMessage, style: style),
      ),
    );
  }
}

/// [child] [height] high while the column has room for it. With less room
/// it shrinks, down to [minHeight] or to the height of its content,
/// whichever is larger; that least height is also its intrinsic height, so
/// a scroll view that fills the screen grows only when even that does not
/// fit.
class _ShrinkableHeight extends SingleChildRenderObjectWidget {
  const new({
    required this.height,
    required this.minHeight,
    required super.child,
  });

  final double height;
  final double minHeight;

  @override
  _RenderShrinkableHeight createRenderObject(BuildContext context) =>
      _RenderShrinkableHeight(height: height, minHeight: minHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderShrinkableHeight renderObject,
  ) {
    renderObject
      ..height = height
      ..minHeight = minHeight;
  }
}

class _RenderShrinkableHeight extends RenderProxyBox {
  new({required this._height, required this._minHeight});

  double _height;
  double get height => _height;
  set height(double value) {
    if (value == _height) return;
    _height = value;
    markNeedsLayout();
  }

  double _minHeight;
  double get minHeight => _minHeight;
  set minHeight(double value) {
    if (value == _minHeight) return;
    _minHeight = value;
    markNeedsLayout();
  }

  /// The least height for [width]: [minHeight], or the content if taller.
  double _least(double width) =>
      math.max(_minHeight, child?.getMaxIntrinsicHeight(width) ?? 0);

  @override
  double computeMinIntrinsicHeight(double width) => _least(width);

  @override
  double computeMaxIntrinsicHeight(double width) => _least(width);

  Size _sizeFor(BoxConstraints constraints) {
    final height = math.max(
      _least(constraints.maxWidth),
      math.min(_height, constraints.maxHeight),
    );
    return constraints.constrain(Size(constraints.maxWidth, height));
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => _sizeFor(constraints);

  @override
  void performLayout() {
    size = _sizeFor(constraints);
    child?.layout(BoxConstraints.tight(size));
  }
}

/// "Modalità demo": the box and the text toggle it.
class _DemoCheckbox extends StatelessWidget {
  const new({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Checkbox(
          value: value,
          semanticLabel: demoChoiceLabel,
          onChanged: enabled ? (value) => onChanged(value ?? false) : null,
        ),
        GestureDetector(
          onTap: enabled ? () => onChanged(!value) : null,
          child: Text(
            demoChoiceLabel,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ],
    );
  }
}
