import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_admob_ads_manager_platform_interface.dart';

/// An implementation of [FlutterAdmobAdsManagerPlatform] that uses method channels.
class MethodChannelFlutterAdmobAdsManager extends FlutterAdmobAdsManagerPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_admob_ads_manager');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
