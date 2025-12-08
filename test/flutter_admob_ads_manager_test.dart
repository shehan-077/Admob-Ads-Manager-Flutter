import 'package:flutter_test/flutter_test.dart';
// import 'package:flutter_admob_ads_manager/flutter_admob_ads_manager.dart';
import 'package:flutter_admob_ads_manager/flutter_admob_ads_manager_platform_interface.dart';
// import 'package:flutter_admob_ads_manager/flutter_admob_ads_manager_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterAdmobAdsManagerPlatform
    with MockPlatformInterfaceMixin
    implements FlutterAdmobAdsManagerPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  // final FlutterAdmobAdsManagerPlatform initialPlatform = FlutterAdmobAdsManagerPlatform.instance;

  // test('$MethodChannelFlutterAdmobAdsManager is the default instance', () {
  //   expect(initialPlatform, isInstanceOf<MethodChannelFlutterAdmobAdsManager>());
  // });

  // test('getPlatformVersion', () async {
  //   FlutterAdmobAdsManager flutterAdmobAdsManagerPlugin = FlutterAdmobAdsManager();
  //   MockFlutterAdmobAdsManagerPlatform fakePlatform = MockFlutterAdmobAdsManagerPlatform();
  //   FlutterAdmobAdsManagerPlatform.instance = fakePlatform;

  //   expect(await flutterAdmobAdsManagerPlugin.getPlatformVersion(), '42');
  // });
}
