/// Version shown in the About section. Release builds pass `--dart-define=APP_VERSION=<pubspec
/// version>` (tool/build_web.sh does); the default keeps debug runs honest.
/// `test/app_info_test.dart` fails if the default drifts from pubspec.yaml.
const String kAppVersion =
    String.fromEnvironment('APP_VERSION', defaultValue: '1.0.1+2');
const String kAppName = 'AuraSOS';
