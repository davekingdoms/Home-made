import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:homemade/core/remote/remote_failure.dart';
import 'package:homemade/core/router/screen_catalog.dart';
import 'package:homemade/core/router/startup_redirect.dart';
import 'package:homemade/design/content_column.dart';
import 'package:homemade/design/cookie.dart';
import 'package:homemade/features/household/cash_amount.dart';
import 'package:homemade/features/household/create_household_screen.dart'
    show noConnectionMessage, startDateExpiredMessage;
import 'package:homemade/features/household/household_dates.dart';
import 'package:homemade/features/household/household_fields.dart';
import 'package:homemade/features/household/household_repository.dart';
import 'package:homemade/features/household/invite_code.dart';
import 'package:homemade/features/household/invite_screen.dart'
    show householdFullMessage;
import 'package:homemade/features/startup/startup_gate.dart';
import 'package:homemade/theme/app_colors.dart';
import 'package:homemade/theme/app_text_theme.dart';
import 'package:homemade/theme/dimens.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

/// Title of A10.
const joinTitle = 'Entra con un invito';

/// Texts of the phase of the code.
const joinCodePhrase = 'Scrivi il codice di 8 caratteri che hai ricevuto.';
const inviteCodeLabel = "Codice d'invito";
const joinContinueLabel = 'Continua';
const joinLinkHint =
    'Se hai ricevuto un link, aprilo su questo dispositivo: il codice si '
    'compila da solo.';

/// What A10 says under the field of the code for an error of the invite.
String inviteErrorText(InviteError error) => switch (error) {
  InviteError.expired =>
    'Questo invito è scaduto: chiedine uno nuovo a chi ti ha invitato.',
  InviteError.used => 'Questo invito è già stato usato.',
  InviteError.revoked => 'Questo invito è stato annullato.',
  InviteError.tooManyAttempts => "Troppi tentativi: riprova tra un'ora.",
  _ => 'Codice non valido. Controlla e riprova.',
};

/// Snackbar of "Continua" when the preview fails for any other reason.
const previewFailedMessage = "Non è stato possibile leggere l'invito. Riprova.";

/// Texts of the phase of the preview.
const householdRegionLabel = 'Casa che ti invita';
const joinStartDateLabel = 'La tua data di inizio';
const joinCashHelper =
    'Facoltativo. È il saldo iniziale del tuo conto Contanti.';
const joinLabel = 'Entra';

/// Snackbars of "Entra".
const demoMismatchMessage =
    'Gli account demo e gli altri account non possono stare nella stessa '
    'casa.';
const alreadyMemberMessage = 'Fai già parte di una casa.';
const joinFailedMessage = 'Non è stato possibile entrare nella casa. Riprova.';

/// The first word of [name]: "Anna Maria" is "Anna".
String _firstWord(String name) => name.trim().split(RegExp(r'\s+')).first;

/// "Ti invita Anna", with the first word of the name of who invites.
String invitedByText(String inviterName) =>
    'Ti invita ${_firstWord(inviterName)}';

/// The first words of the names of the members: "Anna", "Anna e Bruno",
/// "Anna, Bruno e Carla".
String memberNamesText(List<String> names) {
  final words = [for (final name in names) _firstWord(name)];
  if (words.length < 2) return words.join();
  return '${words.sublist(0, words.length - 1).join(', ')} e ${words.last}';
}

/// "Tiene i conti dal 1° novembre 2026".
String keepsAccountsSinceText(DateTime householdStart) =>
    'Tiene i conti dal ${formatItalianDate(householdStart)}';

/// The helper of the start date: how far back it goes, or why it cannot
/// change.
String joinStartDateHelper(DateTime householdStart, DateTime today) {
  if (householdStart.isBefore(today)) {
    return 'Puoi anticiparla fino al ${formatItalianDate(householdStart)}.';
  }
  if (isSameDay(householdStart, today)) {
    return 'La casa parte oggi: la tua data di inizio è la stessa.';
  }
  return 'La casa parte il ${formatItalianDate(householdStart)}: la tua '
      'data di inizio è la stessa.';
}

/// What the screen reader says of the start date [date] on [today]; with
/// [editable], how it changes: back from today, otherwise to any other day.
String joinStartDateSemantics(
  DateTime date,
  DateTime today, {
  required bool editable,
}) {
  final text = formatItalianDate(date);
  final isToday = isSameDay(date, today);
  final spoken = isToday ? 'oggi, $text' : text;
  if (!editable) return '$joinStartDateLabel: $spoken';
  final hint = isToday ? 'Tocca per anticiparla' : 'Tocca per cambiarla';
  return '$joinStartDateLabel: $spoken. $hint';
}

/// The text of the box of information under the fields.
String joinInfoText(DateTime householdStart, DateTime today) =>
    householdStart.isAfter(today)
    ? 'La casa parte il ${formatItalianDate(householdStart)}: da quel giorno '
          'le quote predefinite sono uguali per tutti, e potrete cambiarle '
          'nelle impostazioni.'
    : 'Parti con il conguaglio a zero e non vedi i movimenti precedenti '
          'alla tua data di inizio. Dalla tua data di inizio le quote '
          'predefinite sono uguali per tutti: potrete cambiarle nelle '
          'impostazioni.';

/// Join with an invite (A10, `docs/spec/accesso.md`, section 8), in two
/// phases on the same screen.
///
/// The code: "Codice d'invito", in two groups of 4, and "Continua", which
/// asks `invite_preview`; the errors of the invite under the field. The
/// preview: the household, the start date (from today back to the one of
/// the household; fixed when the household starts today or later), the
/// cash when the start date is today, and "Entra", which calls
/// `redeem_invite`.
///
/// From the link of a pending invite the preview is asked at once with its
/// token; if it fails the phase of the code shows the code of the link and
/// the error under it. Back from the preview returns to the code; from the
/// code to A7, and the pending invite goes.
class JoinHouseholdScreen extends ConsumerStatefulWidget {
  const new({super.key});

  /// Height of "Continua" and "Entra".
  static const double buttonHeight = 56;

  /// Size of the cookies of the members.
  static const double memberCookieSize = 32;

  @override
  ConsumerState<JoinHouseholdScreen> createState() =>
      _JoinHouseholdScreenState();
}

class _JoinHouseholdScreenState extends ConsumerState<JoinHouseholdScreen> {
  final _code = TextEditingController();
  final _cash = TextEditingController();

  /// Token of the pending invite, while the code is still the one of its
  /// link: then the server is asked with the token.
  String? _token;

  /// Code of the pending invite, as the field got it.
  String? _linkCode;

  /// Error of the invite, under the field of the code.
  InviteError? _error;

  /// The household of the invite: the phase of the preview, until back.
  InvitePreview? _preview;

  late DateTime _startDate;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final invite = ref.read(startupGateProvider).pendingInvite;
    if (invite != null) {
      _token = invite.token;
      _linkCode = invite.code;
      _code.text = formatInviteCode(invite.code);
    }
    _code.addListener(_onCodeChanged);
    if (invite != null) unawaited(_askPreview());
  }

  @override
  void dispose() {
    _code.dispose();
    _cash.dispose();
    super.dispose();
  }

  /// Today on this device.
  DateTime _today() => dateOnly(ref.read(wallClockProvider)());

  String get _normalizedCode => normalizeInviteCode(_code.text);

  /// The code the error is about.
  String? _errorCode;

  /// The error goes when the code changes; a code other than the one of
  /// the link is asked by code.
  void _onCodeChanged() {
    final code = _normalizedCode;
    if (_linkCode != null && code != _linkCode) {
      _token = null;
      _linkCode = null;
    }
    if (_error != null && code != _errorCode) {
      setState(() => _error = null);
    } else {
      setState(() {});
    }
  }

  void _showError(InviteError error) {
    setState(() {
      _error = error;
      _errorCode = _normalizedCode;
      _preview = null;
    });
    final view = View.maybeOf(context);
    if (view != null) {
      unawaited(
        SemanticsService.sendAnnouncement(
          view,
          inviteErrorText(error),
          TextDirection.ltr,
        ),
      );
    }
  }

  /// "Continua", or the link: asks the preview of the invite.
  Future<void> _askPreview() async {
    final token = _token;
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(householdRepositoryProvider)
          .previewInvite(
            code: token == null ? _normalizedCode : null,
            token: token,
          );
      if (!mounted) return;
      setState(() => _busy = false);
      final preview = result.preview;
      if (preview == null) {
        final error = result.error ?? InviteError.invalid;
        developer.log('preview invite failed: ${error.key}', name: 'household');
        _showError(error);
        return;
      }
      final today = _today();
      setState(() {
        _preview = preview;
        _startDate = preview.householdStartDate.isBefore(today)
            ? today
            : preview.householdStartDate;
      });
    } on Object catch (error) {
      developer.log(
        'preview invite failed: ${_logCode(error)}',
        name: 'household',
      );
      if (!mounted) return;
      setState(() => _busy = false);
      _tell(
        _failure(error) == RemoteFailure.connection
            ? noConnectionMessage
            : previewFailedMessage,
      );
    }
  }

  Future<void> _pickDate() async {
    final preview = _preview;
    if (preview == null) return;
    final today = _today();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: preview.householdStartDate,
      lastDate: today,
      currentDate: today,
    );
    if (picked == null || !mounted) return;
    setState(() => _startDate = dateOnly(picked));
  }

  Future<void> _join() async {
    final preview = _preview;
    if (preview == null) return;
    final gate = ref.read(startupGateProvider);
    final today = _today();
    final notStarted = preview.householdStartDate.isAfter(today);
    // The cash goes only when the start date is today at the tap.
    final cash = isSameDay(_startDate, today)
        ? parseCashCents(_cash.text)
        : null;
    final token = _token;
    setState(() => _busy = true);
    try {
      final error = await ref
          .read(householdRepositoryProvider)
          .redeemInvite(
            code: token == null ? _normalizedCode : null,
            token: token,
            cashOpeningCents: cash,
            startDate: notStarted ? null : _startDate,
          );
      if (error == null) {
        // The router leaves this screen: the indicator stays until then.
        await gate.householdJoined();
        return;
      }
      developer.log('join household failed: ${error.key}', name: 'household');
      if (error == InviteError.alreadyMember) {
        if (mounted) _tell(alreadyMemberMessage);
        await gate.householdJoined(reread: true);
        return;
      }
      if (!mounted) return;
      setState(() => _busy = false);
      if (error.aboutInvite) {
        _showError(error);
        return;
      }
      _tell(switch (error) {
        InviteError.householdFull => householdFullMessage,
        InviteError.demoMismatch => demoMismatchMessage,
        InviteError.startDateOutOfRange => startDateExpiredMessage,
        _ => joinFailedMessage,
      });
    } on Object catch (error) {
      developer.log(
        'join household failed: ${_logCode(error)}',
        name: 'household',
      );
      if (!mounted) return;
      setState(() => _busy = false);
      _tell(
        _failure(error) == RemoteFailure.connection
            ? noConnectionMessage
            : joinFailedMessage,
      );
    }
  }

  /// Back: from the preview to the code; from the code to A7, and the
  /// pending invite goes.
  Future<void> _back() async {
    if (_busy) return;
    if (_preview != null) {
      setState(() => _preview = null);
      return;
    }
    final from = GoRouterState.of(context)
        .uri
        .queryParameters[destinationParameter];
    await ref.read(startupGateProvider).forgetInvite();
    if (!mounted) return;
    context.go(
      Uri(
        path: screenByCode('A7').path,
        queryParameters: from == null ? null : {destinationParameter: from},
      ).toString(),
    );
  }

  void _tell(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  /// Code of [error] for the log: a key the app does not know, or the code
  /// of the request.
  static String _logCode(Object error) => switch (error) {
    UnknownInviteError(:final key) => key,
    StateError() => 'unreadable answer',
    _ => remoteErrorCode(error),
  };

  /// An answer the app cannot read is no missing network.
  static RemoteFailure _failure(Object error) =>
      error is UnknownInviteError || error is StateError
      ? RemoteFailure.server
      : RemoteFailure.of(error);

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_back());
      },
      child: Scaffold(
        appBar: AppBar(
          // The title next to the back arrow, as in the board of A10.
          titleSpacing: 0,
          title: const Text(joinTitle),
        ),
        body: preview == null ? _codePhase(context) : _previewPhase(preview),
      ),
    );
  }

  /// The code as the board writes it: 22, regular, tabular figures, the
  /// characters 3 apart.
  static TextStyle? _codeStyle(ThemeData theme) {
    final style = theme.textTheme.titleLarge;
    if (style == null) return null;
    return withWeight(style, FontWeight.w400).amount.copyWith(letterSpacing: 3);
  }

  Widget _codePhase(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final error = _error;
    final ready = _normalizedCode.length == inviteCodeLength;
    return _JoinLayout(
      blocks: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          child: Text(
            joinCodePhrase,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        TextField(
          controller: _code,
          enabled: !_busy,
          style: _codeStyle(theme),
          decoration: InputDecoration(
            labelText: inviteCodeLabel,
            errorText: error == null ? null : inviteErrorText(error),
            suffixIcon: error == null
                ? null
                : Icon(Symbols.error_rounded, color: scheme.error),
          ),
          keyboardType: TextInputType.text,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          inputFormatters: const [InviteCodeFormatter()],
          onSubmitted: (_) {
            if (ready && !_busy) unawaited(_askPreview());
          },
        ),
        _MainButton(
          label: joinContinueLabel,
          busy: _busy,
          onPressed: ready && !_busy ? () => unawaited(_askPreview()) : null,
        ),
      ],
      footer: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
        child: Text(
          joinLinkHint,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: context.appColors.testoTerziario,
          ),
        ),
      ),
    );
  }

  Widget _previewPhase(InvitePreview preview) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = _today();
    final householdStart = preview.householdStartDate;
    final editable = householdStart.isBefore(today);
    return _JoinLayout(
      blocks: [
        _HouseholdCard(preview: preview),
        StartDateField(
          label: joinStartDateLabel,
          text: formatStartDate(_startDate, today),
          semanticLabel: joinStartDateSemantics(
            _startDate,
            today,
            editable: editable,
          ),
          helper: joinStartDateHelper(householdStart, today),
          onTap: editable && !_busy ? () => unawaited(_pickDate()) : null,
        ),
        if (isSameDay(_startDate, today))
          CashField(controller: _cash, enabled: !_busy, helper: joinCashHelper),
        DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppRadii.inner),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.sm,
              children: [
                Icon(
                  Symbols.info_rounded,
                  size: AppSizes.iconSmall,
                  color: scheme.onSurfaceVariant,
                ),
                Expanded(
                  child: Text(
                    joinInfoText(householdStart, today),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      footer: _MainButton(
        label: joinLabel,
        busy: _busy,
        onPressed: _busy ? null : () => unawaited(_join()),
      ),
    );
  }
}

/// Body of A10: [blocks] from 8 under the top bar, 24 apart, in the centred
/// column; [footer] at the bottom while it fits, otherwise after them, 24
/// above the edge. The whole column scrolls, with large text or with the
/// keyboard.
class _JoinLayout extends StatelessWidget {
  const new({required this.blocks, required this.footer});

  final List<Widget> blocks;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.paddingOf(context);
    return LayoutBuilder(
      builder: (context, constraints) => CustomScrollView(
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: ContentColumn.sidePadding(constraints.maxWidth, insets)
                  .copyWith(
                    top: AppSpacing.xs,
                    bottom: AppSpacing.xl + insets.bottom,
                  ),
              child: ContentColumn(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (index, block) in blocks.indexed) ...[
                      if (index > 0)
                        const SizedBox(height: AppSpacing.sectionGap),
                      block,
                    ],
                    const Spacer(),
                    const SizedBox(height: AppSpacing.sectionGap),
                    footer,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A filled button 56 high, as wide as the column; [busy] shows the
/// indicator in place of its text.
class _MainButton extends StatelessWidget {
  const new({required this.label, required this.onPressed, this.busy = false});

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => FilledButton(
    style: const ButtonStyle(
      minimumSize: WidgetStatePropertyAll(
        Size.fromHeight(JoinHouseholdScreen.buttonHeight),
      ),
    ),
    onPressed: busy ? null : onPressed,
    child: busy
        ? Semantics(
            label: label,
            child: const SizedBox.square(
              dimension: AppSizes.iconSmall,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        : Text(label),
  );
}

/// The household of the invite, read as the region "Casa che ti invita":
/// who invites, the name, the cookies and the names of the members, since
/// when it keeps the accounts.
class _HouseholdCard extends StatelessWidget {
  const new({required this.preview});

  final InvitePreview preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final secondary = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final inviter = preview.inviterName;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: householdRegionLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: AppSpacing.sm,
            children: [
              if (inviter != null && inviter.trim().isNotEmpty)
                Text(invitedByText(inviter), style: secondary),
              Text(preview.householdName, style: theme.textTheme.titleLarge),
              Row(
                spacing: AppSpacing.sm,
                children: [
                  ExcludeSemantics(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: AppSpacing.xxs,
                      children: [
                        for (final name in preview.memberNames)
                          CookieAvatar(
                            name: _firstWord(name),
                            size: JoinHouseholdScreen.memberCookieSize,
                            style: theme.textTheme.labelLarge,
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Text(
                      memberNamesText(preview.memberNames),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
              Text(
                keepsAccountsSinceText(preview.householdStartDate),
                style: secondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
