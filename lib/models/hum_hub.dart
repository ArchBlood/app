import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:humhub/app_flavored.dart';
import 'package:humhub/app_opener.dart';
import 'package:humhub/models/global_package_info.dart';
import 'package:humhub/models/manifest.dart';
import 'package:humhub/util/log.dart';
import 'package:humhub/util/openers/universal_opener_controller.dart';
import 'package:humhub/util/permission_handler.dart';
import 'package:humhub/util/storage_service.dart';
import 'package:loggy/loggy.dart';
import 'package:permission_handler/permission_handler.dart';

enum RedirectAction { opener, webView }

class HumHub {
  Manifest? manifest;
  String? manifestUrl;
  bool isHideOpener;
  String? randomHash;
  String? appVersion;
  String? pushToken;
  final bool isIos = Platform.isIOS || Platform.isMacOS;
  final bool isAndroid = Platform.isAndroid;

  HumHub(
      {this.manifest, this.manifestUrl, this.isHideOpener = false, this.randomHash, this.appVersion, this.pushToken});

  Map<String, dynamic> toJson() => {
        'manifest': manifest?.toJson(),
        'manifestUri': manifestUrl,
        'isHideDialog': isHideOpener,
        'randomHash': randomHash,
        'appVersion': appVersion,
        'pushToken': pushToken,
      };

  factory HumHub.fromJson(Map<String, dynamic> json) {
    return HumHub(
      manifest: json['manifest'] != null ? Manifest.fromJson(json['manifest']) : null,
      manifestUrl: json['manifestUri'],
      isHideOpener: json['isHideDialog'] as bool,
      randomHash: json['randomHash'],
      appVersion: json['appVersion'],
      pushToken: json['pushToken'],
    );
  }

  Future<RedirectAction> action(ref) async {
    if (!isHideOpener) {
      return RedirectAction.opener;
    } else {
      if (manifest != null) {
        UniversalOpenerController openerController = UniversalOpenerController(url: manifest!.baseUrl);
        String? manifestUrl = await openerController.findManifest(manifest!.baseUrl);
        if (manifestUrl == null) {
          return RedirectAction.opener;
        } else {
          return RedirectAction.webView;
        }
      }
      return RedirectAction.webView;
    }
  }

  static String generateHash(int length) {
    final random = Random.secure();
    const characters = '0123456789abcdef';
    return List.generate(length, (_) => characters[random.nextInt(characters.length)]).join();
  }

  Map<String, String> get customHeaders => {
        'x-humhub-app-token': randomHash!,
        'x-humhub-app': appVersion ?? '1.0.0',
        'x-humhub-app-ostate': isHideOpener ? '1' : '0',
        'x-humhub-app-is-ios': isIos ? '1' : '0',
        'x-humhub-app-is-android': isAndroid ? '1' : '0'
      };

  static Future<Widget> init() async {
    Loggy.initLoggy(
      logPrinter: const GlobalLog(),
    );
    WidgetsFlutterBinding.ensureInitialized();
    await SecureStorageService.clearSecureStorageOnReinstall();
    await GlobalPackageInfo.init();
    await PermissionHandler.requestPermissions(
      [Permission.notification, Permission.camera, Permission.microphone, Permission.storage, Permission.photos],
    );
    switch (GlobalPackageInfo.info.packageName) {
      case 'com.humhub.app':
        return const OpenerApp();
      default:
        await dotenv.load(fileName: "assets/.env");
        return const FlavoredApp();
    }
  }
}
