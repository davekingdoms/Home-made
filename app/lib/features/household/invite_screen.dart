import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:homemade/core/links/text_sharer.dart';
import 'package:homemade/core/remote/remote_failure.dart';
import 'package:homemade/design/content_column.dart';
import 'package:homemade/design/qr_code_box.dart';
import 'package:homemade/features/household/create_household_screen.dart'
    show noConnectionMessage;
import 'package:homemade/features/household/household_dates.dart';
import 'package:homemade/features/household/household_repository.dart';
import 'package:homemade/features/household/invite_code.dart';
import 'package:homemade/features/household/invite_link.dart';
import 'package:homemade/features/startup/startup_gate.dart';
import 'package:homemade/theme/app_button_styles.dart';
import 'package:homemade/theme/app_text_theme.dart';
import 'package:homemade/theme/dimens.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

/// Title of A9.
const inviteTitle = 'Invita';

/// Phrase at the top of A9.
const invitePhrase =
    'Ogni invito vale per una persona, una sola volta, per 7 giorni.';

/// Title of the open invites, and the name of one without a label.
const openInvitesTitle = 'Inviti aperti';
const unnamedInvite = 'Invito senza nome';

/// Field of the label of the invite.
const inviteLabelLabel = 'Per chi (facoltativo)';
const inviteLabelHelper = "Serve solo a riconoscere l'invito nell'elenco.";

/// Longest label of an invite, after removing the spaces at both ends.
const maxInviteLabelLength = 40;

/// Buttons of A9.
const createInviteLabel = "Crea l'invito";
const copyCodeLabel = 'Copia codice';
const copyLinkLabel = 'Copia link';
const shareInviteLabel = "Condividi l'invito";
const inviteAnotherLabel = "Invita un'altra persona";
const inviteLaterLabel = 'Più tardi';
const inviteContinueLabel = 'Continua';

/// Texts of the card of the invite.
const inviteRegionLabel = 'Invito';
const inviteQrLabel = "QR del link d'invito";
const inviteCodeCaption = 'Codice';

/// Snackbars of A9.
const codeCopiedMessage = 'Codice copiato.';
const linkCopiedMessage = 'Link copiato.';
const householdFullMessage = 'Questa casa ha già il numero massimo di membri.';
const createInviteFailedMessage =
    "Non è stato possibile creare l'invito. Riprova.";

/// "Scade il 24 novembre", with the year only when it is not the one of
/// [today].
String inviteExpiryText(DateTime expiresAt, DateTime today) =>
    'Scade il ${formatItalianDayInYear(expiresAt, today)}';

/// The text A9 hands to the share sheet.
String inviteShareText({
  required String householdName,
  required Uri link,
  required String code,
  required DateTime expiresAt,
  required DateTime today,
}) =>
    'Ti invito nella casa «$householdName» su Home-made.\n'
    'Apri questo link sul telefono: $link\n'
    "Oppure, nell'app, tocca «Ho un invito» e scrivi il codice "
    '${formatInviteCode(code)}.\n'
    "L'invito vale fino al ${formatItalianDayInYear(expiresAt, today)}.";

/// Invite (A9, `docs/spec/accesso.md`, section 7), right after "Crea" of
/// A8: the open invites of the household, "Per chi (facoltativo)" and
/// "Crea l'invito"; once the invite exists, its card with the QR of the
/// link, the code and the expiry, the copies, the share, "Invita un'altra
/// persona". At the bottom "Più tardi", which becomes "Continua" once an
/// invite of this visit is shared or copied.
///
/// No invite is created when the screen opens: it would take a place for
/// 7 days even with "Più tardi". The token of the link exists only in
/// memory, while the screen shows its invite.
class InviteScreen extends ConsumerStatefulWidget {
  const new({super.key});

  /// Height of the filled buttons, of the tonal ones, of the text button.
  static const double mainButtonHeight = 56;
  static const double copyButtonHeight = AppSizes.compactButtonHeight;
  static const double textButtonHeight = AppSizes.minTouchTarget;

  /// Smallest height of a row of the open invites.
  static const double openInviteMinHeight = 56;

  @override
  ConsumerState<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends ConsumerState<InviteScreen> {
  final _label = TextEditingController();

  /// Name of the household, for the text of the share; null until read.
  String? _householdName;

  /// Open invites, the latest first: the ones read, and the ones made in
  /// this visit once "Invita un'altra persona" moves them here.
  List<OpenInvite> _openInvites = const [];

  /// The invite on screen, with the token of its link.
  CreatedInvite? _invite;
  DateTime? _inviteExpiresAt;

  bool _creating = false;

  /// Whether an invite of this visit was shared or copied: "Più tardi"
  /// becomes "Continua".
  bool _handedOut = false;

  @override
  void initState() {
    super.initState();
    unawaited(_readContext().catchError((Object _) {}));
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  DateTime _now() => ref.read(wallClockProvider)();

  /// Reads the name and the open invites of the household. A failure is
  /// logged and thrown: at the opening the list just stays empty.
  Future<void> _readContext() async {
    try {
      final context = await ref
          .read(householdRepositoryProvider)
          .readInviteContext();
      if (!mounted) return;
      setState(() {
        _householdName = context.householdName;
        _openInvites = context.openInvites;
      });
    } on Object catch (error) {
      developer.log(
        'read invites failed: ${remoteErrorCode(error)}',
        name: 'household',
      );
      rethrow;
    }
  }

  Future<void> _create() async {
    final label = _label.text.trim();
    setState(() => _creating = true);
    try {
      // Without the name the invite could not be shared.
      if (_householdName == null) await _readContext();
      final invite = await ref
          .read(householdRepositoryProvider)
          .createInvite(label: label.isEmpty ? null : label);
      if (!mounted) return;
      setState(() {
        _creating = false;
        _invite = invite;
        _inviteExpiresAt = _now().add(const Duration(days: 7));
        _label.text = label;
      });
    } on Object catch (error) {
      final known = CreateInviteError.of(error);
      developer.log(
        'create invite failed: ${known?.key ?? remoteErrorCode(error)}',
        name: 'household',
      );
      if (!mounted) return;
      setState(() => _creating = false);
      // An answer the app cannot read is no missing network.
      final failure = error is StateError
          ? RemoteFailure.server
          : RemoteFailure.of(error);
      _tell(switch ((known, failure)) {
        (CreateInviteError.householdFull, _) => householdFullMessage,
        (_, RemoteFailure.connection) => noConnectionMessage,
        _ => createInviteFailedMessage,
      });
    }
  }

  Uri _link(CreatedInvite invite) => ref
      .read(inviteLinksProvider)
      .link(token: invite.token, code: invite.code);

  Future<void> _copy(String text, String message) async {
    setState(() => _handedOut = true);
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) _tell(message);
  }

  Future<void> _share(CreatedInvite invite) async {
    setState(() => _handedOut = true);
    await ref.read(textSharerProvider)(
      inviteShareText(
        householdName: _householdName ?? '',
        link: _link(invite),
        code: invite.code,
        expiresAt: _inviteExpiresAt!,
        today: _now(),
      ),
    );
  }

  /// "Invita un'altra persona": the invite on screen goes among the open
  /// ones, and the field is empty again.
  void _inviteAnother() {
    final invite = _invite;
    if (invite == null) return;
    setState(() {
      _openInvites = [
        OpenInvite(
          id: invite.id,
          label: invite.label,
          expiresAt: _inviteExpiresAt!,
          createdAt: _now(),
        ),
        ..._openInvites,
      ];
      _invite = null;
      _inviteExpiresAt = null;
      _label.clear();
    });
  }

  void _close() => ref.read(startupGateProvider).inviteDone();

  void _tell(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = dateOnly(_now());
    final invite = _invite;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text(inviteTitle),
        ),
        body: _InviteLayout(
          blocks: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
              child: Text(
                invitePhrase,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (_openInvites.isNotEmpty)
              _OpenInvites(invites: _openInvites, today: today),
            Padding(
              // Room above the field for its label, as in the board.
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: TextField(
                controller: _label,
                readOnly: invite != null,
                enabled: !_creating || invite != null,
                decoration: const InputDecoration(
                  labelText: inviteLabelLabel,
                  helperText: inviteLabelHelper,
                ),
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(maxInviteLabelLength),
                ],
              ),
            ),
            if (invite == null)
              _MainButton(
                icon: Symbols.add_link_rounded,
                label: createInviteLabel,
                busy: _creating,
                onPressed: _creating ? null : () => unawaited(_create()),
              )
            else ...[
              _InviteCard(
                link: _link(invite).toString(),
                code: invite.code,
                expiry: inviteExpiryText(_inviteExpiresAt!, today),
                onCopyCode: () => unawaited(
                  _copy(formatInviteCode(invite.code), codeCopiedMessage),
                ),
                onCopyLink: () => unawaited(
                  _copy(_link(invite).toString(), linkCopiedMessage),
                ),
              ),
              _MainButton(
                icon: Symbols.share_rounded,
                label: shareInviteLabel,
                onPressed: () => unawaited(_share(invite)),
              ),
              Center(
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(
                      AppSizes.minTouchTarget,
                      InviteScreen.textButtonHeight,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                  ),
                  onPressed: _inviteAnother,
                  icon: const Icon(
                    Symbols.person_add_rounded,
                    size: AppSizes.iconSmall,
                  ),
                  label: const Text(inviteAnotherLabel),
                ),
              ),
            ],
          ],
          footer: OutlinedButton(
            onPressed: _close,
            child: Text(_handedOut ? inviteContinueLabel : inviteLaterLabel),
          ),
        ),
      ),
    );
  }
}

/// Body of A9: [blocks] 16 apart under the top bar, in the centred column;
/// [footer] at the bottom while it fits, otherwise after them, 24 above the
/// edge. The whole column scrolls, with large text or with the keyboard.
class _InviteLayout extends StatelessWidget {
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
              padding: ContentColumn.sidePadding(
                constraints.maxWidth,
                insets,
              ).copyWith(bottom: AppSpacing.xl + insets.bottom),
              child: ContentColumn(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (index, block) in blocks.indexed) ...[
                      if (index > 0) const SizedBox(height: AppSpacing.md),
                      block,
                    ],
                    const Spacer(),
                    const SizedBox(height: AppSpacing.md),
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

/// A filled button 56 high with [icon], as wide as the column; [busy]
/// shows the indicator in place of its content.
class _MainButton extends StatelessWidget {
  const new({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    const style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(
        Size.fromHeight(InviteScreen.mainButtonHeight),
      ),
    );
    if (busy) {
      return FilledButton(
        style: style,
        onPressed: null,
        child: Semantics(
          label: label,
          child: const SizedBox.square(
            dimension: AppSizes.iconSmall,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return FilledButton.icon(
      style: style,
      onPressed: onPressed,
      icon: Icon(icon, size: AppSizes.iconSmall),
      label: Text(label),
    );
  }
}

/// "Inviti aperti": one row for each invite, the latest first, with the
/// label (or "Invito senza nome") and the expiry. No action: revoking is in
/// the settings of the household.
class _OpenInvites extends StatelessWidget {
  const new({required this.invites, required this.today});

  final List<OpenInvite> invites;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.xs,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          child: Semantics(
            header: true,
            child: Text(
              openInvitesTitle,
              style: theme.textTheme.titleSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        for (final invite in invites)
          MergeSemantics(
            child: Container(
              constraints: const BoxConstraints(
                minHeight: InviteScreen.openInviteMinHeight,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppRadii.inner),
              ),
              child: Row(
                spacing: AppSpacing.sm,
                children: [
                  Icon(
                    Symbols.schedule_rounded,
                    size: AppSizes.icon,
                    color: scheme.onSurfaceVariant,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          invite.label ?? unnamedInvite,
                          style: theme.textTheme.bodyLarge,
                        ),
                        Text(
                          inviteExpiryText(invite.expiresAt, today),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// The card of the invite, read as the region "Invito": the QR of the link
/// on the left; the code, read one character at a time, and the expiry on
/// the right; under them "Copia codice" and "Copia link".
class _InviteCard extends StatelessWidget {
  const new({
    required this.link,
    required this.code,
    required this.expiry,
    required this.onCopyCode,
    required this.onCopyLink,
  });

  final String link;
  final String code;
  final String expiry;
  final VoidCallback onCopyCode;
  final VoidCallback onCopyLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final copyStyle = context.buttonStyles.tonal.merge(
      context.buttonStyles.compact,
    );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: inviteRegionLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.md,
            children: [
              Row(
                spacing: AppSpacing.md,
                children: [
                  QrCodeBox(data: link, semanticLabel: inviteQrLabel),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        Semantics(
                          container: true,
                          label:
                              '$inviteCodeCaption: ${spokenInviteCode(code)}',
                          excludeSemantics: true,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 2,
                            children: [
                              Text(
                                inviteCodeCaption,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                formatInviteCode(code),
                                style: theme.textTheme.headlineSmall?.amount
                                    .copyWith(letterSpacing: 2),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          expiry,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Row(
                spacing: AppSpacing.xs,
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      style: copyStyle,
                      onPressed: onCopyCode,
                      icon: const Icon(
                        Symbols.content_copy_rounded,
                        size: AppSizes.iconSmall,
                      ),
                      label: const Text(copyCodeLabel),
                    ),
                  ),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      style: copyStyle,
                      onPressed: onCopyLink,
                      icon: const Icon(
                        Symbols.link_rounded,
                        size: AppSizes.iconSmall,
                      ),
                      label: const Text(copyLinkLabel),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
