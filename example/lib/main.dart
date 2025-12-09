import 'package:flutter/material.dart';
import 'package:admob_ads_manager/admob_ads_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final ids = AdMobIds.single(
    appId: "appId",
    interstitialId: "interstitialId",
    bannerId: "bannerId",
    appOpenId: "appOpenId",
    rewardedId: "rewardedId",
    nativeId: "nativeId",
    rewardedIntId: "rewardedIntId",
  );

  await AdsManager.instance.init(
    ids: ids,
    status: AdsStatus.testing,
    loadingColor: Colors.red,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: const HomePage());
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  void _showInterstitial(BuildContext context) {
    AdsManager.instance.showInterstitial(context, 0, _SimpleRequestHandler());
  }

  void _showRewarded(BuildContext context) {
    AdsManager.instance.showRewarded(context, 0, _SimpleRewardHandler());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ads Manager Demo')),
      body: Column(
        children: [
          ElevatedButton(
            onPressed: () => _showInterstitial(context),
            child: const Text('Show Interstitial'),
          ),
          ElevatedButton(
            onPressed: () => _showRewarded(context),
            child: const Text('Show Rewarded'),
          ),
          const Spacer(),
          // Banner
          const BannerAdContainer(index: 0),
          const Spacer(),
          // Native
          const NativeAdsContainer(index: 0, size: NativeAdsSize.small),
          const SizedBox(height: 10),
          const NativeAdsContainer(index: 0, size: NativeAdsSize.medium),
        ],
      ),
    );
  }
}

class _SimpleRequestHandler implements RequestHandler {
  @override
  void onError(String error) {
    debugPrint('Interstitial error: $error');
  }

  @override
  void onSuccess() {
    debugPrint('Interstitial success / dismissed');
  }
}

class _SimpleRewardHandler implements RewardedRequestHandler {
  @override
  void onDismissed() {
    debugPrint('Reward dismissed');
  }

  @override
  void onError(String error) {
    debugPrint('Reward error: $error');
  }

  @override
  void onFailedToShow(String error) {
    debugPrint('Reward failed to show: $error');
  }

  @override
  void onRewarded() {
    debugPrint('User rewarded!');
  }

  @override
  void onShowed() {
    debugPrint('Reward showed');
  }
}
