import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:homemade/core/config/app_config.dart';
import 'package:homemade/core/links/link_opener.dart';
import 'package:homemade/core/remote/remote_failure.dart';
import 'package:homemade/design/content_column.dart';
import 'package:homemade/design/cookie.dart';
import 'package:homemade/features/auth/auth_repository.dart';
import 'package:homemade/features/auth/sign_out.dart';
import 'package:homemade/features/startup/account_status.dart';
import 'package:homemade/features/startup/startup_gate.dart';
import 'package:homemade/theme/app_colors.dart';
import 'package:homemade/theme/dimens.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

/// Longest display name, as the check of `profiles` counts it: characters
/// after removing the spaces at both ends.
const maxDisplayNameLength = 80;

/// Title and phrase of the whole first access.
const welcomeTitle = 'Il tuo profilo';
const welcomePhrase =
    'Gli altri membri della casa ti vedranno con questo nome e questa foto.';

/// Title and phrase of A3 with a new version of the notice only.
const noticeUpdatedTitle = 'Informativa aggiornata';
const noticeUpdatedPhrase =
    "L'informativa privacy è cambiata. Leggila e conferma per continuare.";

/// Helper text of the name.
const nameHelperText = 'Preso da Google: puoi cambiarlo.';

/// Line of A3 for a demo account, under the helper text of the name.
const demoAccountNotice =
    'Account demo: si potrà eliminare da Impostazioni › Account.';

/// Text of the checkbox of the privacy notice.
const noticeCheckboxLabel = "Ho letto l'informativa privacy";

/// Text of the button that opens the privacy notice.
const readNoticeLabel = "Leggi l'informativa";

/// Line under the checkbox, at the whole first access only.
const noticeVersionLine =
    'Home-made registra quale versione hai letto e quando.';

/// Whether [name], without the spaces at both ends, fits `profiles`.
bool isValidDisplayName(String name) {
  final length = name.trim().runes.length;
  return length >= 1 && length <= maxDisplayNameLength;
}

/// First access (A3, `docs/spec/accesso.md`, section 4): "Il tuo profilo"
/// with the photo and the name of the Google account, the card of the
/// checkbox of the privacy notice and "Continua" at the bottom. With a new
/// version of the notice and the profile already saved, "Informativa
/// aggiornata" with the card of the checkbox only.
class WelcomeScreen extends ConsumerStatefulWidget {
  const new({super.key});

  /// Height of "Continua".
  static const double buttonHeight = 56;

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

enum _MenuAction { signOut }

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  // Read in initState: with the checkbox alone the name field never shows,
  // and dispose must not be the first to read the session.
  late final SessionUser? _user;
  late final TextEditingController _name;

  bool _noticeRead = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _user = ref.read(authRepositoryProvider).currentUser;
    _name = TextEditingController(text: _user?.name?.trim() ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _openNotice() {
    final uri = ref.read(appConfigProvider).pagesUri(privacyNoticePath);
    unawaited(ref.read(linkOpenerProvider)(uri));
  }

  Future<void> _continue({required bool noticeOnly}) async {
    setState(() => _saving = true);
    try {
      await ref
          .read(startupGateProvider)
          .saveFirstAccess(
            displayName: noticeOnly ? null : _name.text.trim(),
            avatarUrl: noticeOnly ? null : _user?.avatarUrl,
          );
      // The router leaves this screen: the indicator stays until then.
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      final message = switch (RemoteFailure.of(error)) {
        RemoteFailure.connection =>
          'Nessuna connessione. Controlla la rete e riprova.',
        RemoteFailure.server => 'Non è stato possibile salvare. Riprova.',
      };
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final gate = ref.watch(startupGateProvider);
    return Scaffold(
      appBar: AppBar(
        actions: [
          PopupMenuButton<_MenuAction>(
            icon: const Icon(Symbols.more_vert_rounded),
            onSelected: (_) => unawaited(confirmSignOut(context, ref)),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _MenuAction.signOut,
                child: Text("Esci dall'account"),
              ),
            ],
          ),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: gate,
        builder: (context, state, _) {
          final noticeOnly = state.noticeOnly;
          final canContinue =
              !_saving &&
              _noticeRead &&
              (noticeOnly || isValidDisplayName(_name.text));
          return _WelcomeLayout(
            blocks: [
              _Heading(
                title: noticeOnly ? noticeUpdatedTitle : welcomeTitle,
                phrase: noticeOnly ? noticeUpdatedPhrase : welcomePhrase,
              ),
              if (!noticeOnly) ...[
                Center(
                  child: _AccountPhoto(
                    name: _name.text.trim(),
                    url: _user?.avatarUrl,
                  ),
                ),
                TextField(
                  controller: _name,
                  enabled: !_saving,
                  decoration: InputDecoration(
                    labelText: 'Nome',
                    // The line of a demo account goes under the helper text,
                    // in its style: the helper of a field has none of its
                    // own.
                    helper: DefaultTextStyle.merge(
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: AppSpacing.xxs,
                        children: [
                          const Text(nameHelperText),
                          if (state.demo) const Text(demoAccountNotice),
                        ],
                      ),
                    ),
                  ),
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(maxDisplayNameLength),
                  ],
                  onChanged: (_) => setState(() {}),
                ),
              ],
              _NoticeCard(
                value: _noticeRead,
                enabled: !_saving,
                versionLine: !noticeOnly,
                onChanged: (value) => setState(() => _noticeRead = value),
                onRead: _openNotice,
              ),
            ],
            button: FilledButton(
              style: const ButtonStyle(
                minimumSize: WidgetStatePropertyAll(
                  Size.fromHeight(WelcomeScreen.buttonHeight),
                ),
              ),
              onPressed: canContinue
                  ? () => unawaited(_continue(noticeOnly: noticeOnly))
                  : null,
              child: _saving
                  ? const SizedBox.square(
                      dimension: AppSizes.iconSmall,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Continua'),
            ),
          );
        },
      ),
    );
  }
}

/// Body of A3: [blocks] from just under the top bar, 24 apart, in the
/// centred column; [button] at the bottom while it fits, otherwise after
/// them. The whole column scrolls, with large text or with the keyboard.
class _WelcomeLayout extends StatelessWidget {
  const new({required this.blocks, required this.button});

  final List<Widget> blocks;
  final Widget button;

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
                      if (index > 0)
                        const SizedBox(height: AppSpacing.sectionGap),
                      block,
                    ],
                    const Spacer(),
                    const SizedBox(height: AppSpacing.sectionGap),
                    button,
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

/// Title and phrase at the top of A3.
class _Heading extends StatelessWidget {
  const new({required this.title, required this.phrase});

  final String title;
  final String phrase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.xs,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: theme.textTheme.headlineLarge),
          ),
          Text(
            phrase,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The photo of the Google account on a cookie; without a photo, or when it
/// does not load, the initial of [name].
class _AccountPhoto extends StatelessWidget {
  const new({required this.name, required this.url});

  /// Twice the avatar of the hub.
  static const double size = AppSizes.hubAvatar * 2;

  final String name;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final initials = CookieAvatar(
      name: name,
      size: size,
      style: Theme.of(context).textTheme.displaySmall,
    );
    final url = this.url;
    if (url == null) return initials;
    return ExcludeSemantics(
      child: ClipPath(
        clipper: const ShapeBorderClipper(shape: CookieBorder()),
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => initials,
        ),
      ),
    );
  }
}

/// The card of the privacy notice: the checkbox, whose row toggles it
/// whole, "Leggi l'informativa" and, with [versionLine], the line on what
/// Home-made records.
class _NoticeCard extends StatelessWidget {
  const new({
    required this.value,
    required this.enabled,
    required this.versionLine,
    required this.onChanged,
    required this.onRead,
  });

  /// Least height of the row of the checkbox.
  static const double _rowHeight = 56;

  /// Height of "Leggi l'informativa" and of its icon.
  static const double _readHeight = 40;
  static const double _readIconSize = 18;

  /// Part of the touch target of "Leggi l'informativa" (48) around the
  /// button (40), above and below it: the room under it is smaller by as
  /// much.
  static const double _touchSlack = (AppSizes.minTouchTarget - _readHeight) / 2;

  final bool value;
  final bool enabled;
  final bool versionLine;
  final ValueChanged<bool> onChanged;
  final VoidCallback onRead;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const bottom = AppSpacing.sm;
    return Card(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.xs,
          AppSpacing.xxs,
          AppSpacing.xs,
          versionLine ? bottom : bottom - _touchSlack,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MergeSemantics(
              child: InkWell(
                onTap: enabled ? () => onChanged(!value) : null,
                borderRadius: BorderRadius.circular(AppRadii.inner),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: _rowHeight),
                  child: Row(
                    spacing: AppSpacing.xxs,
                    children: [
                      SizedBox.square(
                        dimension: AppSizes.minTouchTarget,
                        child: Center(
                          child: Checkbox(
                            value: value,
                            onChanged: enabled
                                ? (value) => onChanged(value ?? false)
                                : null,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          noticeCheckboxLabel,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: AppSpacing.xs),
              child: TextButton(
                style: const ButtonStyle(
                  minimumSize: WidgetStatePropertyAll(
                    Size(AppSizes.minTouchTarget, _readHeight),
                  ),
                  padding: WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                  ),
                ),
                onPressed: onRead,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: AppSpacing.xxs,
                  children: [
                    Flexible(child: Text(readNoticeLabel)),
                    Icon(Symbols.open_in_new_rounded, size: _readIconSize),
                  ],
                ),
              ),
            ),
            if (versionLine)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xs,
                  AppSpacing.xxs - _touchSlack,
                  AppSpacing.xs,
                  0,
                ),
                child: Text(
                  noticeVersionLine,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: context.appColors.testoTerziario,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
