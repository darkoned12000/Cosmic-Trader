import 'dart:io';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart' show SystemNavigator;

/// True on Linux / macOS / Windows (a native window exists).
bool isDesktopPlatform() =>
    defaultTargetPlatform == TargetPlatform.linux ||
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.windows;

/// Terminates the app cleanly and returns the user to the OS desktop.
///
/// On desktop, [exit] kills the process directly, bypassing Flutter's shell
/// teardown — closing the last window on this engine build logs
/// "'FlutterEngineRemoveView' returned 'kInvalidArguments'". All state must
/// already be flushed by the caller, so nothing is lost.
///
/// On mobile, [SystemNavigator.pop] asks the OS to close the app. On web
/// there is no native process to exit, so this is a no-op (web users just
/// close the browser tab).
void quitApplication() {
  if (kIsWeb) return; // No native process to exit on web.
  if (isDesktopPlatform()) {
    exit(0);
  } else {
    SystemNavigator.pop();
  }
}
