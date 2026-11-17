// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'appearance.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The appearance of the whole app: Teal and Automatico until the user
/// chooses otherwise.
///
/// In memory only: the choice is saved with the Settings.

@ProviderFor(AppearanceController)
final appearanceControllerProvider = AppearanceControllerProvider._();

/// The appearance of the whole app: Teal and Automatico until the user
/// chooses otherwise.
///
/// In memory only: the choice is saved with the Settings.
final class AppearanceControllerProvider
    extends $NotifierProvider<AppearanceController, Appearance> {
  /// The appearance of the whole app: Teal and Automatico until the user
  /// chooses otherwise.
  ///
  /// In memory only: the choice is saved with the Settings.
  AppearanceControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appearanceControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appearanceControllerHash();

  @$internal
  @override
  AppearanceController create() => AppearanceController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Appearance value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Appearance>(value),
    );
  }
}

String _$appearanceControllerHash() =>
    r'2537cdeaf8fbade1b7afa3a301ec29bc18bb1416';

/// The appearance of the whole app: Teal and Automatico until the user
/// chooses otherwise.
///
/// In memory only: the choice is saved with the Settings.

abstract class _$AppearanceController extends $Notifier<Appearance> {
  Appearance build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<Appearance, Appearance>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Appearance, Appearance>,
              Appearance,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
