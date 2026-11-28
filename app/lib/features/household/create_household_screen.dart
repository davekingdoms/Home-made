import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:homemade/core/remote/remote_failure.dart';
import 'package:homemade/design/content_column.dart';
import 'package:homemade/features/household/cash_amount.dart';
import 'package:homemade/features/household/household_dates.dart';
import 'package:homemade/features/household/household_fields.dart';
import 'package:homemade/features/household/household_repository.dart';
import 'package:homemade/features/startup/startup_gate.dart';
import 'package:homemade/theme/dimens.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

export 'package:homemade/features/household/household_fields.dart'
    show cashLabel;

/// Longest name of a household, as the check of `households` counts it:
/// characters after removing the spaces at both ends.
const maxHouseholdNameLength = 80;

/// Title of A8.
const createHouseholdTitle = 'Crea casa';

/// Labels of the fields of A8.
const householdNameLabel = 'Nome della casa';
const startDateLabel = 'Data di inizio';

/// Helper texts of the fields of A8.
const startDateHelper =
    "L'app considera solo i movimenti da questa data. Le banche di solito "
    'restituiscono circa tre mesi di movimenti: collegale subito dopo.';
const cashHelper =
    "Facoltativo. È il saldo iniziale del tuo conto Contanti, non un'entrata: "
    'puoi indicarlo anche dopo.';

/// Text of the button of A8.
const createHouseholdLabel = 'Crea';

/// Messages of A8 when "Crea" fails.
const noConnectionMessage = 'Nessuna connessione. Controlla la rete e riprova.';
const startDateExpiredMessage =
    "La data di inizio non è più valida: scegline un'altra.";
const createFailedMessage = 'Non è stato possibile creare la casa. Riprova.';

/// Whether [name], without the spaces at both ends, fits `households`.
bool isValidHouseholdName(String name) {
  final length = name.trim().runes.length;
  return length >= 1 && length <= maxHouseholdNameLength;
}

/// What the screen reader says of the start date [date] on [today].
String startDateSemantics(DateTime date, DateTime today) {
  final text = formatItalianDate(date);
  final spoken = isSameDay(date, today) ? 'oggi, $text' : text;
  return '$startDateLabel: $spoken. Tocca per cambiarla';
}

/// Create a household (A8, `docs/spec/accesso.md`, section 6): the name,
/// the start date and, when the start date is today, the cash the user has
/// now; "Crea" at the bottom.
///
/// "Crea" calls `create_household` with an id generated when the screen
/// opens and the same at every retry: the function creates nothing the
/// second time. Then the startup moves on.
class CreateHouseholdScreen extends ConsumerStatefulWidget {
  const new({super.key});

  /// Height of "Crea".
  static const double buttonHeight = 56;

  @override
  ConsumerState<CreateHouseholdScreen> createState() =>
      _CreateHouseholdScreenState();
}

class _CreateHouseholdScreenState extends ConsumerState<CreateHouseholdScreen> {
  /// Id of the household, the same at every retry.
  final String _id = const Uuid().v4();

  final _name = TextEditingController();
  final _cash = TextEditingController();

  late DateTime _startDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _startDate = defaultStartDate(_today());
  }

  @override
  void dispose() {
    _name.dispose();
    _cash.dispose();
    super.dispose();
  }

  /// Today on this device.
  DateTime _today() => dateOnly(ref.read(wallClockProvider)());

  Future<void> _pickDate() async {
    final today = _today();
    final picked = await showDatePicker(
      context: context,
      initialDate: clampStartDate(_startDate, today),
      firstDate: firstStartDate(today),
      lastDate: lastStartDate(today),
      currentDate: today,
    );
    if (picked == null || !mounted) return;
    setState(() => _startDate = dateOnly(picked));
  }

  Future<void> _create() async {
    final gate = ref.read(startupGateProvider);
    // The cash goes only when the start date is today at the tap.
    final cash = isSameDay(_startDate, _today())
        ? parseCashCents(_cash.text)
        : null;
    setState(() => _saving = true);
    try {
      await ref
          .read(householdRepositoryProvider)
          .createHousehold(
            id: _id,
            name: _name.text.trim(),
            startDate: _startDate,
            cashOpeningCents: cash,
          );
      // The router leaves this screen for A9: the indicator stays until
      // then.
      await gate.householdCreated();
    } on Object catch (error) {
      final known = CreateHouseholdError.of(error);
      if (known == CreateHouseholdError.alreadyMember) {
        // A household made, or an invite used, on another device: nothing
        // to say, the startup goes on.
        await gate.householdJoined(reread: true);
        return;
      }
      developer.log(
        'create household failed: ${known?.key ?? remoteErrorCode(error)}',
        name: 'household',
      );
      if (!mounted) return;
      setState(() => _saving = false);
      final message = switch ((known, RemoteFailure.of(error))) {
        (CreateHouseholdError.startDateOutOfRange, _) =>
          startDateExpiredMessage,
        (_, RemoteFailure.connection) => noConnectionMessage,
        _ => createFailedMessage,
      };
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = _today();
    final withCash = isSameDay(_startDate, today);
    final canCreate = !_saving && isValidHouseholdName(_name.text);
    return Scaffold(
      appBar: AppBar(
        // The title next to the back arrow, as in the board of A8.
        titleSpacing: 0,
        title: const Text(createHouseholdTitle),
      ),
      body: _CreateLayout(
        fields: [
          TextField(
            controller: _name,
            enabled: !_saving,
            decoration: const InputDecoration(labelText: householdNameLabel),
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            inputFormatters: [
              LengthLimitingTextInputFormatter(maxHouseholdNameLength),
            ],
            onChanged: (_) => setState(() {}),
          ),
          StartDateField(
            label: startDateLabel,
            text: formatStartDate(_startDate, today),
            semanticLabel: startDateSemantics(_startDate, today),
            helper: startDateHelper,
            onTap: _saving ? null : () => unawaited(_pickDate()),
          ),
          if (withCash)
            CashField(controller: _cash, enabled: !_saving, helper: cashHelper),
        ],
        button: FilledButton(
          style: const ButtonStyle(
            minimumSize: WidgetStatePropertyAll(
              Size.fromHeight(CreateHouseholdScreen.buttonHeight),
            ),
          ),
          onPressed: canCreate ? () => unawaited(_create()) : null,
          child: _saving
              ? const SizedBox.square(
                  dimension: AppSizes.iconSmall,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text(createHouseholdLabel),
        ),
      ),
    );
  }
}

/// Body of A8: [fields] from 16 under the top bar, 24 apart, in the centred
/// column; [button] at the bottom while it fits, otherwise after them. The
/// whole column scrolls, with large text or with the keyboard.
class _CreateLayout extends StatelessWidget {
  const new({required this.fields, required this.button});

  final List<Widget> fields;
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
              padding: ContentColumn.sidePadding(constraints.maxWidth, insets)
                  .copyWith(
                    top: AppSpacing.md,
                    bottom: AppSpacing.xl + insets.bottom,
                  ),
              child: ContentColumn(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (index, field) in fields.indexed) ...[
                      if (index > 0)
                        const SizedBox(height: AppSpacing.sectionGap),
                      field,
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
