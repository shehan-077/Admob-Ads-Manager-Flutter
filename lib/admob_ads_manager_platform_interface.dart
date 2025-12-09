import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'admob_ads_manager_method_channel.dart';

abstract class FlutterAdmobAdsManagerPlatform extends PlatformInterface {
  /// Constructs a FlutterAdmobAdsManagerPlatform.
  FlutterAdmobAdsManagerPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterAdmobAdsManagerPlatform _instance =
      MethodChannelFlutterAdmobAdsManager();

  /// The default instance of [FlutterAdmobAdsManagerPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterAdmobAdsManager].
  static FlutterAdmobAdsManagerPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterAdmobAdsManagerPlatform] when
  /// they register themselves.
  static set instance(FlutterAdmobAdsManagerPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
