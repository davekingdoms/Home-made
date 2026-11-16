import 'dart:io';
import 'dart:ui';

import 'package:homemade/theme/tokens.dart';

/// The six combinations of palette and brightness, in the order of the
/// columns of the table in section 2.1 of the style specification.
const combinations = <(AppPalette, Brightness)>[
  (AppPalette.teal, Brightness.dark),
  (AppPalette.teal, Brightness.light),
  (AppPalette.dollari, Brightness.dark),
  (AppPalette.dollari, Brightness.light),
  (AppPalette.mauriziani, Brightness.dark),
  (AppPalette.mauriziani, Brightness.light),
];

/// Headers of those columns in the specification.
const combinationHeaders = [
  'Teal scuro',
  'Teal chiaro',
  'Dollari scuro',
  'Dollari chiaro',
  'Mauriziani scuro',
  'Mauriziani chiaro',
];

/// Name of a combination in the test descriptions.
String describeCombination((AppPalette, Brightness) combination) =>
    '${combination.$1.name} ${combination.$2.name}';

// Tests run from app/: the specification is in the repository root.
List<String> _readStyleSpec() =>
    File('../docs/spec/stile.md').readAsLinesSync();

/// The table of section 2.1: its column headers and, for each column, the
/// colour of every role.
({List<String> headers, List<Map<String, Color>> columns}) readPaletteTable() {
  final lines = _readStyleSpec();
  final start = lines.indexWhere((line) => line.startsWith('### 2.1'));
  final columns = List.generate(
    combinations.length,
    (_) => <String, Color>{},
  );
  var headers = <String>[];
  for (final line in lines.skip(start + 1)) {
    if (line.startsWith('#')) break;
    if (!line.startsWith('|')) continue;
    // "| a | b |" splits into an empty cell, the cells and an empty cell.
    final cells = line.split('|').map((cell) => cell.trim()).toList();
    if (cells.length != combinations.length + 3) continue;
    if (cells[1] == 'Ruolo') {
      headers = cells.sublist(2, cells.length - 1);
      continue;
    }
    final role = RegExp(r'^`(\w+)`$').firstMatch(cells[1])?[1];
    if (role == null) continue;
    for (var column = 0; column < combinations.length; column++) {
      columns[column][role] = parseSpecColor(cells[column + 2]);
    }
  }
  return (headers: headers, columns: columns);
}

/// The house roles of section 9.2 (Teal, night), in the order they are
/// written.
Map<String, Color> readCasaRoles() {
  const marker = '**Ruoli (Teal, notte):** ';
  final line = _readStyleSpec().firstWhere((line) => line.contains(marker));
  final list = line.substring(line.indexOf(marker) + marker.length);
  return {
    for (final [name, value] in list.split(' · ').map(
      (role) => role.replaceFirst(RegExp(r'\.$'), '').split(' '),
    ))
      name: parseSpecColor(value),
  };
}

/// A colour as the specification writes it: `#RRGGBB` or `trasparente`.
Color parseSpecColor(String value) {
  if (value == 'trasparente') return const Color.fromARGB(0, 0, 0, 0);
  if (!RegExp(r'^#[0-9A-F]{6}$').hasMatch(value)) {
    throw FormatException('Not a colour of the specification', value);
  }
  final rgb = int.parse(value.substring(1), radix: 16);
  return Color.fromARGB(255, rgb >> 16, (rgb >> 8) % 256, rgb % 256);
}
