import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:homemade/core/config/app_config.dart';
import 'package:homemade/core/links/link_opener.dart';
import 'package:homemade/core/remote/remote_failure.dart';
import 'package:homemade/design/cookie.dart';
import 'package:homemade/design/phone_layout.dart';
import 'package:homemade/features/auth/auth_repository.dart';
import 'package:homemade/features/auth/sign_out.dart';
import 'package:homemade/features/startup/account_status.dart';
import 'package:homemade/features/startup/startup_gate.dart';
import 'package:homemade/theme/dimens.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

/// Longest display name, as the check of `profiles` counts it: characters
/// after removing the spaces at both ends.
const maxDisplayNameLength = 80;

/// Line of A3 for a demo account, under the name.
const demoAccountNotice =
    'Account demo: si potrà eliminare da Impostazioni › Account.';

/// Whether [name], without the spaces at both ends, fits `profiles`.
bool isValidDisplayName(String name) {
  final length = name.trim().runes.length;
  return length >= 1 && length <= maxDisplayNameLength;
}

/// First access (A3): the photo and the name of the Google account, the
/// checkbox of the privacy notice and "Continua" (`docs/spec/accesso.md`,
/// section 4). With a new version of the notice and the profile already
/// saved, only the checkbox.
class WelcomeScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

enum _MenuAction { signOut }

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  late final SessionUser? _user = ref.read(authRepositoryProvider).currentUser;
  late final TextEditingController _name = TextEditingController(
    text: _user?.name?.trim() ?? '',
  );
  late final TapGestureRecognizer _noticeLink = TapGestureRecognizer()
    ..onTap = _openNotice;

  bool _noticeRead = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _noticeLink.dispose();
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
      body: SafeArea(
        child: ValueListenableBuilder(
          valueListenable: gate,
          builder: (context, state, _) {
            final noticeOnly = state.noticeOnly;
            final canContinue =
                !_saving &&
                _noticeRead &&
                (noticeOnly || isValidDisplayName(_name.text));
            return PhoneLayout(
              children: [
                if (!noticeOnly) ...[
                  Center(
                    child: _AccountPhoto(
                      name: _name.text.trim(),
                      url: _user?.avatarUrl,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  TextField(
                    controller: _name,
                    enabled: !_saving,
                    decoration: const InputDecoration(labelText: 'Nome'),
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(maxDisplayNameLength),
                    ],
                    onChanged: (_) => setState(() {}),
                  ),
                  if (state.demo) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      demoAccountNotice,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                ],
                _NoticeCheckbox(
                  value: _noticeRead,
                  enabled: !_saving,
                  link: _noticeLink,
                  onChanged: (value) => setState(() => _noticeRead = value),
                ),
                const SizedBox(height: AppSpacing.xl),
                FilledButton(
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
              ],
            );
          },
        ),
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
    final initials = CookieAvatar(name: name, size: size);
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

/// "Ho letto l'informativa privacy": the box and the text toggle it, the
/// words "informativa privacy" open the notice.
class _NoticeCheckbox extends StatelessWidget {
  const new({
    required this.value,
    required this.enabled,
    required this.link,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final TapGestureRecognizer link;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Checkbox(
          value: value,
          semanticLabel: "Ho letto l'informativa privacy",
          onChanged: enabled ? (value) => onChanged(value ?? false) : null,
        ),
        Expanded(
          child: GestureDetector(
            onTap: enabled ? () => onChanged(!value) : null,
            child: Text.rich(
              TextSpan(
                text: "Ho letto l'",
                children: [
                  TextSpan(
                    text: 'informativa privacy',
                    recognizer: link,
                    style: TextStyle(
                      color: scheme.primary,
                      decoration: TextDecoration.underline,
                      decorationColor: scheme.primary,
                    ),
                  ),
                ],
              ),
              style: theme.textTheme.bodyLarge,
            ),
          ),
        ),
      ],
    );
  }
}
