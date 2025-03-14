import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

class IntentState {
  final List<SharedMediaFile>? _sharedFiles;
  final String? sharedText;
  final Object? error;
  final Uri? initialUri;
  final Uri? latestUri;

  IntentState({
    List<SharedMediaFile>? sharedFiles,
    this.sharedText,
    this.error,
    this.initialUri,
    this.latestUri,
  }) : _sharedFiles = sharedFiles;

  bool isSharedFilesNullOrEmpty() {
    return _sharedFiles == null || _sharedFiles.isEmpty;
  }

  IntentState copyWith({
    List<SharedMediaFile>? sharedFiles,
    String? sharedText,
    Object? error,
    Uri? initialUri,
    Uri? latestUri,
  }) {
    return IntentState(
      sharedFiles: sharedFiles ?? _sharedFiles,
      sharedText: sharedText ?? this.sharedText,
      error: error ?? this.error,
      initialUri: initialUri ?? this.initialUri,
      latestUri: latestUri ?? this.latestUri,
    );
  }
}

class IntentNotifier extends StateNotifier<IntentState> {
  IntentNotifier() : super(IntentState());

  void setSharedFiles(List<SharedMediaFile>? files) {
    state = state.copyWith(sharedFiles: files);
  }

  void setSharedText(String? text) {
    state = state.copyWith(sharedText: text);
  }

  void setError(Object? error) {
    state = state.copyWith(error: error);
  }

  void setInitialUri(Uri? uri) {
    state = state.copyWith(initialUri: uri);
  }

  void setLatestUri(Uri? uri) {
    state = state.copyWith(latestUri: uri);
  }

  List<SharedMediaFile>? useSharedFiles() {
    final files = state._sharedFiles;
    if (files != null) {
      state = state.copyWith(sharedFiles: []);
    }
    return files;
  }

  double  get filesSumSizeMb  {
    if (state._sharedFiles == null) return 0;
    double totalSizeMB = 0.0;
    for (var file in state._sharedFiles!) {
      File fileObj = File(file.path);
      int fileSizeBytes = fileObj.lengthSync();
      double fileSizeMB = fileSizeBytes / (1024 * 1024);
      totalSizeMB += fileSizeMB;
    }
    return totalSizeMB;
  }
}

final intentProvider = StateNotifierProvider<IntentNotifier, IntentState>(
  (ref) => IntentNotifier(),
);
