import 'dart:async';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humhub/util/auth_in_app_browser.dart';
import 'package:humhub/models/channel_message.dart';
import 'package:humhub/models/hum_hub.dart';
import 'package:humhub/models/manifest.dart';
import 'package:humhub/pages/opener.dart';
import 'package:humhub/util/connectivity_plugin.dart';
import 'package:humhub/util/extensions.dart';
import 'package:humhub/util/file_handler.dart';
import 'package:humhub/util/loading_provider.dart';
import 'package:humhub/util/notifications/init_from_push.dart';
import 'package:humhub/util/notifications/plugin.dart';
import 'package:humhub/util/providers.dart';
import 'package:humhub/util/openers/universal_opener_controller.dart';
import 'package:humhub/util/push/provider.dart';
import 'package:humhub/util/router.dart';
import 'package:loggy/loggy.dart';
import 'package:open_file_plus/open_file_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:humhub/util/router.dart' as m;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../util/show_dialog.dart';
import '../util/web_view_global_controller.dart';

class WebView extends ConsumerStatefulWidget {
  const WebView({super.key});
  static const String path = '/web_view';

  @override
  WebViewAppState createState() => WebViewAppState();
}

class WebViewAppState extends ConsumerState<WebView> {
  late AuthInAppBrowser authBrowser;
  late Manifest manifest;
  late URLRequest _initialRequest;
  late PullToRefreshController _pullToRefreshController;
  HeadlessInAppWebView? headlessWebView;

  final _settings = InAppWebViewSettings(
    useShouldOverrideUrlLoading: true,
    useShouldInterceptFetchRequest: true,
    javaScriptEnabled: true,
    supportZoom: false,
    javaScriptCanOpenWindowsAutomatically: true,
    supportMultipleWindows: true,
    useHybridComposition: true,
  );

  @override
  initState() {
    super.initState();
    LoadingProvider.of(ref).dismissAll();
  }

  @override
  Widget build(BuildContext context) {
    _initialRequest = _initRequest;
    _pullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(
        color: HexColor(manifest.themeColor),
      ),
      onRefresh: () async {
        if (Platform.isAndroid) {
          WebViewGlobalController.value?.reload();
        } else if (Platform.isIOS) {
          WebViewGlobalController.value?.loadUrl(
              urlRequest: URLRequest(
                  url: await WebViewGlobalController.value?.getUrl(), headers: ref.read(humHubProvider).customHeaders));
        }
      },
    );
    authBrowser = AuthInAppBrowser(
      manifest: manifest,
      concludeAuth: (URLRequest request) {
        _concludeAuth(request);
      },
    );
    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: () => exitApp(context, ref),
      child: Scaffold(
        backgroundColor: HexColor(manifest.themeColor),
        body: SafeArea(
          bottom: false,
          child: InAppWebView(
            initialUrlRequest: _initialRequest,
            initialSettings: _settings,
            pullToRefreshController: _pullToRefreshController,
            shouldOverrideUrlLoading: _shouldOverrideUrlLoading,
            onWebViewCreated: _onWebViewCreated,
            shouldInterceptFetchRequest: _shouldInterceptFetchRequest,
            onCreateWindow: _onCreateWindow,
            onLoadStop: _onLoadStop,
            onLoadStart: _onLoadStart,
            onProgressChanged: _onProgressChanged,
            onReceivedError: _onReceivedError,
            onDownloadStartRequest: _onDownloadStartRequest,
          ),
        ),
      ),
    );
  }

  URLRequest get _initRequest {
    final args = ModalRoute.of(context)!.settings.arguments;
    String? url;
    if (args is Manifest) {
      manifest = args;
    }
    if (args is UniversalOpenerController) {
      UniversalOpenerController controller = args;
      ref.read(humHubProvider).setInstance(controller.humhub);
      manifest = controller.humhub.manifest!;
      url = controller.url;
    }
    if (args == null) {
      manifest = m.MyRouter.initParams;
    }
    if (args is ManifestWithRemoteMsg) {
      ManifestWithRemoteMsg manifestPush = args;
      manifest = manifestPush.manifest;
      url = manifestPush.remoteMessage.data['url'];
    }
    String? payloadFromPush = InitFromPush.usePayload();
    if (payloadFromPush != null) url = payloadFromPush;
    return URLRequest(url: WebUri(url ?? manifest.startUrl), headers: ref.read(humHubProvider).customHeaders);
  }

  Future<NavigationActionPolicy?> _shouldOverrideUrlLoading(
      InAppWebViewController controller, NavigationAction action) async {
    WebViewGlobalController.ajaxSetHeaders(headers: ref.read(humHubProvider).customHeaders);

    //Open in external browser
    final url = action.request.url!.origin;
    if (!url.startsWith(manifest.baseUrl) && action.isForMainFrame) {
      authBrowser.launchUrl(action.request);
      return NavigationActionPolicy.CANCEL;
    }
    // 2nd Append customHeader if url is in app redirect and CANCEL the requests without custom headers
    if (Platform.isAndroid ||
        action.navigationType == NavigationType.LINK_ACTIVATED ||
        action.navigationType == NavigationType.FORM_SUBMITTED) {
      Map<String, String> mergedMap = {...?_initialRequest.headers, ...?action.request.headers};
      URLRequest newRequest = action.request.copyWith(headers: mergedMap);
      controller.loadUrl(urlRequest: newRequest);
      return NavigationActionPolicy.CANCEL;
    }
    return NavigationActionPolicy.ALLOW;
  }

  _onWebViewCreated(InAppWebViewController controller) async {
    LoadingProvider.of(ref).showLoading();
    headlessWebView = HeadlessInAppWebView();
    headlessWebView!.run();
    await controller.addWebMessageListener(
      WebMessageListener(
        jsObjectName: "flutterChannel",
        onPostMessage: (inMessage, sourceOrigin, isMainFrame, replyProxy) async {
          logInfo(inMessage);
          ChannelMessage message = ChannelMessage.fromJson(inMessage!.data);
          await _handleJSMessage(message, headlessWebView!);
          logDebug('flutterChannel triggered: ${message.type}');
        },
      ),
    );
    WebViewGlobalController.setValue(controller);
  }

  Future<FetchRequest?> _shouldInterceptFetchRequest(InAppWebViewController controller, FetchRequest request) async {
    logDebug("_shouldInterceptFetchRequest");
    request.headers!.addAll(_initialRequest.headers!);
    return request;
  }

  Future<bool?> _onCreateWindow(InAppWebViewController controller, CreateWindowAction createWindowAction) async {
    WebUri? urlToOpen = createWindowAction.request.url;

    if (urlToOpen == null) return Future.value(false);
    if (urlToOpen.rawValue.contains('file/download')) {
      controller.loadUrl(urlRequest: createWindowAction.request);
      return Future.value(false);
    }

    if (await canLaunchUrl(urlToOpen)) {
      await launchUrl(urlToOpen, mode: LaunchMode.externalApplication);
    } else {
      logError('Could not launch $urlToOpen');
    }

    return Future.value(true);
  }

  _onLoadStop(InAppWebViewController controller, Uri? url) {
    // Disable remember me checkbox on login and set def. value to true: check if the page is actually login page, if it is inject JS that hides element
    if (url!.path.contains('/user/auth/login')) {
      WebViewGlobalController.value!
          .evaluateJavascript(source: "document.querySelector('#login-rememberme').checked=true");
      WebViewGlobalController.value!.evaluateJavascript(
          source:
              "document.querySelector('#account-login-form > div.form-group.field-login-rememberme').style.display='none';");
    }
    WebViewGlobalController.ajaxSetHeaders(headers: ref.read(humHubProvider).customHeaders);
    LoadingProvider.of(ref).dismissAll();
  }

  void _onLoadStart(InAppWebViewController controller, Uri? url) async {
    WebViewGlobalController.ajaxSetHeaders(headers: ref.read(humHubProvider).customHeaders);
  }

  _onProgressChanged(InAppWebViewController controller, int progress) {
    if (progress == 100) {
      _pullToRefreshController.endRefreshing();
    }
  }

  void _onReceivedError(InAppWebViewController controller, WebResourceRequest request, WebResourceError error) {
    if (error.description == 'net::ERR_INTERNET_DISCONNECTED') NoConnectionDialog.show(context);
  }

  _concludeAuth(URLRequest request) {
    authBrowser.close();
    WebViewGlobalController.value!.loadUrl(urlRequest: request);
  }

  Future<void> _handleJSMessage(ChannelMessage message, HeadlessInAppWebView headlessWebView) async {
    switch (message.action) {
      case ChannelAction.showOpener:
        ref.read(humHubProvider).setIsHideOpener(false);
        ref.read(humHubProvider).clearSafeStorage();
        FlutterAppBadger.updateBadgeCount(0);
        Navigator.of(context).pushNamedAndRemoveUntil(Opener.path, (Route<dynamic> route) => false);
        break;
      case ChannelAction.hideOpener:
        ref.read(humHubProvider).setIsHideOpener(true);
        ref.read(humHubProvider).setHash(HumHub.generateHash(32));
        break;
      case ChannelAction.registerFcmDevice:
        String? token = ref.read(pushTokenProvider).value ?? await FirebaseMessaging.instance.getToken();
        if (token != null) {
          WebViewGlobalController.ajaxPost(
            url: message.url!,
            data: '{ token: \'$token\' }',
            headers: ref.read(humHubProvider).customHeaders,
          );
        }
        var status = await Permission.notification.status;
        // status.isDenied: The user has previously denied the notification permission
        // !status.isGranted: The user has never been asked for the notification permission
        bool wasAskedBefore = await NotificationPlugin.hasAskedPermissionBefore();
        // ignore: use_build_context_synchronously
        if (status != PermissionStatus.granted && !wasAskedBefore) ShowDialog.of(context).notificationPermission();
        break;
      case ChannelAction.updateNotificationCount:
        if (message.count != null) FlutterAppBadger.updateBadgeCount(message.count!);
        break;
      case ChannelAction.unregisterFcmDevice:
        String? token = ref.read(pushTokenProvider).value ?? await FirebaseMessaging.instance.getToken();
        if (token != null) {
          WebViewGlobalController.ajaxPost(
            url: message.url!,
            data: '{ token: \'$token\' }',
            headers: ref.read(humHubProvider).customHeaders,
          );
        }
        break;
      case ChannelAction.none:
        break;
    }
  }

  Future<bool> exitApp(context, ref) async {
    bool canGoBack = await WebViewGlobalController.value!.canGoBack();
    if (canGoBack) {
      WebViewGlobalController.value!.goBack();
      return Future.value(false);
    } else {
      final exitConfirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10.0))),
          title: Text(AppLocalizations.of(context)!.web_view_exit_popup_title),
          content: Text(AppLocalizations.of(context)!.web_view_exit_popup_content),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(AppLocalizations.of(context)!.no),
            ),
            TextButton(
              onPressed: () {
                var isHide = ref.read(humHubProvider).isHideDialog;
                isHide
                    ? SystemNavigator.pop()
                    : Navigator.of(context).pushNamedAndRemoveUntil(Opener.path, (Route<dynamic> route) => false);
              },
              child: Text(AppLocalizations.of(context)!.yes),
            ),
          ],
        ),
      );
      return exitConfirmed ?? false;
    }
  }

  void _onDownloadStartRequest(InAppWebViewController controller, DownloadStartRequest downloadStartRequest) async {
    FileHandler(
        downloadStartRequest: downloadStartRequest,
        controller: controller,
        onSuccess: (File file, String filename) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('File downloaded: $filename'),
              action: SnackBarAction(
                label: 'Open',
                onPressed: () {
                  // Open the downloaded file
                  OpenFile.open(file.path);
                },
              ),
            ),
          );
        },
        onError: (er) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Something went wrong'),
            ),
          );
        }).download();
  }

  @override
  void dispose() {
    super.dispose();
    if (headlessWebView != null) {
      headlessWebView!.dispose();
    }
  }
}
