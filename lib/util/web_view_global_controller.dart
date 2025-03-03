import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:humhub/models/global_package_info.dart';
import 'package:humhub/models/global_user_agent.dart';
import 'package:humhub/models/manifest.dart';
import 'package:loggy/loggy.dart';

class WebViewGlobalController {
  static InAppWebViewController? _value;

  static InAppWebViewController? get value => _value;

  /// [openCreateWindowInWebView]
  ///
  /// Determines if a URL should open in a new browser window or within the current web view.
  ///
  /// - Opens in a new window if:
  ///   - The URL is for file downloads (`file/file/download` after base URL).
  ///   - The URL is a @username profile redirect (`/u` after base URL).
  ///   - The URL is a @space redirect (`/s` after base URL).
  ///
  /// [ref] is reference to the app state.
  /// [url] is the URL to evaluate.
  /// @return `true` if the URL should open in a new window, `false` otherwise.
  static bool openCreateWindowInWebView({required String url, required Manifest manifest}) {
    String? baseUrl = manifest.baseUrl;
    if (url.startsWith('$baseUrl/file/file/download')) return true;
    if (url.startsWith('$baseUrl/u')) return true;
    if (url.startsWith('$baseUrl/s')) return true;
    return false;
  }

  static void setValue(InAppWebViewController newValue) {
    _value = newValue;
  }

  static void ajaxPost({required String url, required String data, Map<String, String>? headers}) {
    String jsonHeaders = jsonEncode(headers);
    String jsCode4 = """
          \$.ajax({
              url: '$url',
              type: 'POST',
              data: $data,
              headers: $jsonHeaders,
              async: false, // IMPORTANT: it needs to be sync
          });
    """;
    value?.evaluateJavascript(source: jsCode4);
  }

  static Future<void> ajaxPostFiles({
    required String url,
    required List<dynamic> data,
    Map<String, String>? headers,
    Function(Map<String, dynamic>? response)? onResponse,
  }) async {
    String jsonHeaders = jsonEncode(headers ?? {});
    String jsonData = jsonEncode(data);

    String jsCode = """
        new Promise((resolve, reject) => {
        try {
          var formData = new FormData();
          var parsedData = JSON.parse('$jsonData');
      
          for (var key in parsedData) {
            var value = parsedData[key];
      
            // Decode Base64 string to binary data
            var binaryString = atob(value.base64);
            var binaryLength = binaryString.length;
            var binaryArray = new Uint8Array(binaryLength);
      
            for (var i = 0; i < binaryLength; i++) {
              binaryArray[i] = binaryString.charCodeAt(i);
            }
      
            // Create Blob and File from the decoded binary data
            var blob = new Blob([binaryArray], { type: value.mimeType });
            var file = new File([blob], value.filename, { type: value.mimeType });
      
            // Append file to FormData
            formData.append('files[]', file);
          }
      
          // Make AJAX POST request using fetch
          fetch('$url', {
            method: 'POST',
            body: formData,
            headers: JSON.parse('$jsonHeaders')
          })
            .then(response => {
              if (!response.ok) {
                throw new Error(`HTTP error! status: \${response.status}`);
              }
              return response.json(); // Assuming the server responds with JSON
            })
            .then(data => {
              const jsonString = JSON.stringify(data);
              window.flutter_inappwebview.callHandler('onAjaxSuccess', data);
              resolve(data);
            })
            .catch(error => {
              window.flutter_inappwebview.callHandler('onAjaxError', { status: error.status || 'unknown', error: error.message });
              reject({ status: error.status || 'unknown', error: error.message });
            });
        } catch (e) {
          console.error('Error in AJAX request:', e);
          reject(e);
        }
      });
     """;

    try {
      await value?.evaluateJavascript(source: jsCode);
      if (onResponse != null) {
        value?.addJavaScriptHandler(
          handlerName: 'onAjaxSuccess',
          callback: (args) {
            if (args.isNotEmpty) {
              final response = jsonDecode(args[0].toString());
              onResponse(response);
            } else {
              onResponse(null);
            }
          },
        );

        value?.addJavaScriptHandler(
          handlerName: 'onAjaxError',
          callback: (args) {
            logError('AJAX Error: ${args[0]}');
            onResponse(null);
          },
        );
      }
    } catch (e) {
      logError('Error during ajaxPost execution: $e');
      if (onResponse != null) {
        onResponse(null);
      }
    }
  }

  static void ajaxSetHeaders({Map<String, String>? headers}) {
    String jsCode = "\$.ajaxSetup({headers: ${jsonEncode(headers).toString()}});";
    value?.evaluateJavascript(source: jsCode);
  }

  static void onLongPressHitTestResult(InAppWebViewController controller, InAppWebViewHitTestResult hitResult) async {
    if (hitResult.extra != null && ([InAppWebViewHitTestResultType.SRC_ANCHOR_TYPE, InAppWebViewHitTestResultType.EMAIL_TYPE].contains(hitResult.type))) {
      Clipboard.setData(
        ClipboardData(text: hitResult.extra!),
      );
    }
  }

  static Future<void> listenToImageOpen() async {
    // Inject JavaScript to monitor changes to the blueimp-gallery element
    bool opened = false;
    await _value?.evaluateJavascript(source: """
            // Create a MutationObserver to monitor changes in the #blueimp-gallery element's attributes
            var observer = new MutationObserver(function(mutations) {
              mutations.forEach(function(mutation) {
                var galleryElement = document.getElementById('blueimp-gallery');
                
                // Check if the gallery is opened (display: block)
                if (galleryElement && galleryElement.style.display === 'block') {
                  // Send message to Flutter when the image gallery is opened
                  window.flutter_inappwebview.callHandler('onImageOpened');
                }
                
                // Check if the gallery is closed (display: none)
                if (galleryElement && galleryElement.style.display === 'none') {
                  // Send message to Flutter when the image gallery is closed
                  window.flutter_inappwebview.callHandler('onImageClosed');
                }
              });
            });

            // Observe changes in the style attribute of the #blueimp-gallery element
            var target = document.getElementById('blueimp-gallery');
            if (target) {
              observer.observe(target, { attributes: true, attributeFilter: ['style'] });
            }
          """);

    // Set up JavaScript handlers in Flutter to respond to image opening and closing events
    _value?.addJavaScriptHandler(
      handlerName: 'onImageOpened',
      callback: (args) {
        if (opened) return;
        opened = true;
        _value?.setSettings(settings: settings(zoom: opened));
      },
    );

    _value?.addJavaScriptHandler(
      handlerName: 'onImageClosed',
      callback: (args) async {
        if (!opened) return;
        opened = false;
        zoomOut();
        _value?.setSettings(settings: settings(zoom: opened));
      },
    );
  }

  static void appendViewportFitCover() {
    value?.evaluateJavascript(source: """
    (function() {
      var metaTags = document.getElementsByTagName('meta');
      for (var i = 0; i < metaTags.length; i++) {
        if (metaTags[i].name.toLowerCase() === 'viewport') {
          var content = metaTags[i].content;
          if (!content.includes('viewport-fit=cover')) {
            metaTags[i].content = content + ', viewport-fit=cover';
          }
        }
      }
    })();
  """);
  }

  static Future<void> zoomOut() async {
    bool? canZoomOut = true;
    while (canZoomOut ?? false) {
      canZoomOut = await value?.zoomOut();
    }
  }

  static InAppWebViewSettings settings({bool zoom = false}) {
    return InAppWebViewSettings(
      useShouldOverrideUrlLoading: true,
      useShouldInterceptFetchRequest: false,
      javaScriptEnabled: true,
      javaScriptCanOpenWindowsAutomatically: true,
      supportMultipleWindows: true,
      useHybridComposition: true,
      allowsInlineMediaPlayback: true,
      mediaPlaybackRequiresUserGesture: false,
      supportZoom: zoom ? true : false,
      userAgent: GlobalUserAgent.value,
      applicationNameForUserAgent: GlobalPackageInfo.info.appName,
    );
  }
}
