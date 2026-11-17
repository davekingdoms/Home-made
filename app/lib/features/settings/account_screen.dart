import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:homemade/core/router/screen_catalog.dart';
import 'package:homemade/design/placeholder_screen.dart';
import 'package:homemade/features/auth/auth_repository.dart';
import 'package:material_ui/material_ui.dart';

/// Account (I2), provisional: the placeholder with the "Esci" button and
/// nothing about the user. Once the session is closed the router goes to
/// sign-in (A2).
class AccountScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(screenByCode('I2').label)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const PlaceholderMark(),
            const SizedBox(height: 24),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
              onPressed: () =>
                  unawaited(ref.read(authRepositoryProvider).signOut()),
              child: const Text('Esci'),
            ),
          ],
        ),
      ),
    );
  }
}
