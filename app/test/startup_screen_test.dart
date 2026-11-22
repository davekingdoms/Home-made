import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homemade/design/app_logo.dart';
import 'package:homemade/features/hub/hub_screen.dart';
import 'package:homemade/features/startup/startup_gate.dart';
import 'package:homemade/features/startup/startup_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers/fake_auth_repository.dart';
import 'helpers/fakes.dart';
import 'helpers/pump_app.dart';

const _offlineText = 'Nessuna connessione. Controlla la rete e riprova.';

void main() {
  testWidgets('while the account is read shows only the logo', (tester) async {
    final accounts = FakeAccountRepository()..readGate = Completer<void>();
    final router = await pumpApp(
      tester,
      location: '/finance/summary',
      accounts: accounts,
    );

    expect(router.location, startupPath);
    expect(find.byType(StartupScreen), findsOneWidget);
    expect(find.byType(AppLogo), findsOneWidget);
    expect(find.byType(Text), findsNothing);
    expect(find.byType(HubScreen), findsNothing);

    accounts.readGate!.complete();
    await tester.pumpAndSettle();
    expect(router.location, '/finance/summary');
  });

  testWidgets('offline, the saved state opens the hub', (tester) async {
    final store = MemoryLocalStore();
    store.values[StartupGate.storeKey(anna.id)] = jsonEncode(
      readyAccount.toJson(),
    );
    final router = await pumpApp(
      tester,
      accounts: FakeAccountRepository()..readError = offline,
      store: store,
    );

    expect(router.location, '/');
    expect(find.byType(HubScreen), findsOneWidget);
  });

  testWidgets('offline without a saved state asks to retry', (tester) async {
    final accounts = FakeAccountRepository()..readError = offline;
    final router = await pumpApp(
      tester,
      location: '/settings',
      accounts: accounts,
    );

    expect(router.location, startupPath);
    expect(find.text(_offlineText), findsOneWidget);
    expect(find.text('Riprova'), findsOneWidget);

    accounts.readError = null;
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();

    expect(router.location, '/settings');
  });

  testWidgets('an error of Supabase without a saved state says so', (
    tester,
  ) async {
    await pumpApp(
      tester,
      accounts: FakeAccountRepository()..readError = serverError,
    );

    expect(
      find.text('Non è stato possibile caricare i dati. Riprova.'),
      findsOneWidget,
    );
    expect(find.text(_offlineText), findsNothing);
    expect(find.text('Riprova'), findsOneWidget);
  });

  testWidgets('a read that does not answer ends in the retry screen', (
    tester,
  ) async {
    final accounts = FakeAccountRepository()..readGate = Completer<void>();
    await pumpApp(tester, accounts: accounts);
    expect(find.byType(AppLogo), findsOneWidget);

    await tester.pump(StartupGate.readTimeout);
    await tester.pumpAndSettle();

    expect(find.text(_offlineText), findsOneWidget);
  });
}
