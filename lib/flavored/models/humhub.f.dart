import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:humhub/flavored/models/manifest.f.dart';
import 'package:humhub/models/global_package_info.dart';
import 'package:humhub/models/hum_hub.dart';

class HumHubF extends HumHub {
  @override
  ManifestF get manifest => ManifestF.fromEnv();
  @override
  String get manifestUrl => dotenv.env['MANIFEST_URL']!;

  HumHubF({
    bool isHideOpener = false,
    String? randomHash,
    String? appVersion,
    String? pushToken,
  }) : super(
            isHideOpener: isHideOpener,
            randomHash: HumHub.generateHash(32),
            appVersion: appVersion,
            pushToken: pushToken);

  @override
  Map<String, String> get customHeaders => {
        'x-humhub-app-token': randomHash!,
        'x-humhub-app': appVersion ?? '1.0.0',
        'x-humhub-app-bundle-id': GlobalPackageInfo.info.packageName,
        'x-humhub-app-ostate': isHideOpener ? '1' : '0',
        'x-humhub-app-is-ios': isIos ? '1' : '0',
        'x-humhub-app-is-android': isAndroid ? '1' : '0'
      };

  static Future<HumHubF> initialize() async {
    return HumHubF();
  }
}
