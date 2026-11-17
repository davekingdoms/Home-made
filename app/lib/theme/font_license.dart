import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Asset with the SIL Open Font License of Google Sans Flex.
const fontLicenseAsset = 'assets/fonts/OFL.txt';

/// Adds the licence of the bundled font to the licences page (section 3 of
/// `docs/spec/stile.md`). Call it once, before the app starts.
void registerFontLicense() {
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString(fontLicenseAsset);
    yield LicenseEntryWithLineBreaks(const ['Google Sans Flex'], license);
  });
}
