import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:admob_ads_manager/admob_ads_manager.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isAndroid || Platform.isIOS) {
    final ids = AdMobIds.single(
      appId: "appId",
      interstitialId: "interstitialId",
      bannerId: "bannerId",
      appOpenId: "appOpenId",
      rewardedId: "rewardedId",
      nativeId: "nativeId",
      rewardedIntId: "rewardedIntId",
    );

    if (const bool.fromEnvironment('FORCE_TEST_ADS')) {
      AdsManager.instance.setForceTestAds(true);
    }

    const umpTestDevice = String.fromEnvironment('UMP_TEST_DEVICE');
    const umpEea = bool.fromEnvironment('UMP_EEA');
    const umpReset = bool.fromEnvironment('UMP_RESET');

    if (umpReset) {
      await AdsManager.instance.debugResetConsent();
    }

    await AdsManager.instance.init(
      ids: ids,
      status: AdsStatus.hybrid,
      loadingColor: Colors.black,
      consentDebugSettings: umpTestDevice.isEmpty
          ? null
          : ConsentDebugSettings(
              debugGeography: umpEea
                  ? DebugGeography.debugGeographyEea
                  : DebugGeography.debugGeographyDisabled,
              testIdentifiers: [umpTestDevice],
            ),
    );

    AdsManager.instance.adsAvailable.addListener(
      () => debugPrint(
        'ADS adsAvailable=${AdsManager.instance.adsAvailable.value}',
      ),
    );
    AdsManager.instance.privacyOptionsRequired.addListener(
      () => debugPrint(
        'ADS privacyOptionsRequired=${AdsManager.instance.privacyOptionsRequired.value}',
      ),
    );
    unawaited(
      AdsManager.instance.whenReady().then(
        (ready) => debugPrint(
          'ADS whenReady=$ready sdkInitialized=${AdsManager.instance.isSdkInitialized}',
        ),
      ),
    );

    const autoAppOpenDelay = int.fromEnvironment('AUTO_APP_OPEN_DELAY_MS');
    if (autoAppOpenDelay > 0) {
      WidgetsBinding.instance.addObserver(_LifecycleLogger());
      debugPrint('LIFECYCLE initial=${WidgetsBinding.instance.lifecycleState}');
      unawaited(
        AdsManager.instance.whenReady().then((_) async {
          await Future<void>.delayed(
            const Duration(milliseconds: autoAppOpenDelay),
          );
          final context = navigatorKey.currentContext;
          debugPrint(
            'LIFECYCLE at auto app open: ${WidgetsBinding.instance.lifecycleState}',
          );
          if (context == null || !context.mounted) return;
          await AdsManager.instance.showAppOpen(
            context,
            0,
            RequestHandlerImpl(
              onSuccess: () => debugPrint('Auto app open dismissed'),
              onError: (e) => debugPrint('Auto app open error: $e'),
            ),
          );
        }),
      );
    }

    if (kDebugMode) {
      final manager = AdsManager.instance;
      debugPrint(
        'ADS units banner=${manager.getBannerAdUnitId(0)} '
        'collapsible=${manager.getBannerAdUnitId(0, type: BannerAdsType.collapsible)} '
        'interstitial=${manager.getAdUnitId(AdsUnit.interstitial, 0)} '
        'native=${manager.getAdUnitId(AdsUnit.native, 0)} '
        'appOpen=${manager.getAdUnitId(AdsUnit.appOpen, 0)} '
        'rewarded=${manager.getAdUnitId(AdsUnit.rewarded, 0)} '
        'rewardedInt=${manager.getAdUnitId(AdsUnit.rewardedInt, 0)}',
      );
    }

    unawaited(AdsManager.instance.preLoad(AdsUnit.interstitial, 0));
    unawaited(AdsManager.instance.preLoad(AdsUnit.rewarded, 0));
    unawaited(AdsManager.instance.preLoad(AdsUnit.rewardedInt, 0));
  }

  runApp(const MyApp());
}

class _LifecycleLogger with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('LIFECYCLE $state');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(navigatorKey: navigatorKey, home: const HomePage());
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  void _showInterstitial(BuildContext context) {
    AdsManager.instance.showInterstitial(
      context,
      0,
      RequestHandlerImpl(
        onSuccess: () => debugPrint('Interstitial success / dismissed'),
        onError: (e) => debugPrint('Interstitial error: $e'),
      ),
    );
  }

  void _showRewarded(BuildContext context) {
    AdsManager.instance.showRewarded(
      context,
      0,
      RewardedCallbacks(
        onShowed: () => debugPrint('Reward showed'),
        onRewarded: (reward) =>
            debugPrint('User rewarded: ${reward.amount} ${reward.type}'),
        onDismissed: () => debugPrint('Reward dismissed'),
        onError: (e) => debugPrint('Reward error: $e'),
        onFailedToShow: (e) => debugPrint('Reward failed to show: $e'),
      ),
    );
  }

  void _showAppOpen(BuildContext context) {
    AdsManager.instance.showAppOpen(
      context,
      0,
      RequestHandlerImpl(
        onSuccess: () => debugPrint('App Open success / dismissed'),
        onError: (e) => debugPrint('App Open error: $e'),
      ),
    );
  }

  void _showRewardInt(BuildContext context) {
    AdsManager.instance.showRewardedInterstitial(
      context,
      0,
      RewardedCallbacks(
        onShowed: () => debugPrint('Rewarded Interstitial showed'),
        onRewarded: (reward) =>
            debugPrint('User rewarded: ${reward.amount} ${reward.type}'),
        onDismissed: () => debugPrint('Rewarded Interstitial dismissed'),
        onError: (e) => debugPrint('Rewarded Interstitial error: $e'),
        onFailedToShow: (e) =>
            debugPrint('Rewarded Interstitial failed to show: $e'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ads Manager Demo')),
      body: SingleChildScrollView(
        child: Column(
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: AdsManager.instance.privacyOptionsRequired,
              builder: (context, required, _) => required
                  ? ListTile(
                      leading: const Icon(Icons.privacy_tip_outlined),
                      title: const Text('Privacy settings'),
                      onTap: () => AdsManager.instance.showPrivacyOptionsForm(),
                    )
                  : const SizedBox.shrink(),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: AdsManager.instance.adsAvailable,
              builder: (context, available, _) =>
                  Text('Ads available: $available'),
            ),
            TextButton(
              onPressed: () async {
                final ready = await AdsManager.instance.refreshAvailability();
                debugPrint('ADS refreshAvailability=$ready');
              },
              child: const Text('Refresh availability'),
            ),
            ElevatedButton(
              onPressed: () {
                _showInterstitial(context);
                _showAppOpen(context);
                _showRewarded(context);
                _showRewardInt(context);
              },
              child: const Text('Rapid: request all four'),
            ),
            ElevatedButton(
              onPressed: () => _showInterstitial(context),
              child: const Text('Show Interstitial'),
            ),
            ElevatedButton(
              onPressed: () => _showRewarded(context),
              child: const Text('Show Rewarded'),
            ),
            ElevatedButton(
              onPressed: () => _showAppOpen(context),
              child: const Text('Show App Open'),
            ),
            ElevatedButton(
              onPressed: () => _showRewardInt(context),
              child: const Text('Show Rewarded Interstitial'),
            ),
            const Divider(),
            for (final page in const [
              ('Normal anchored banner', NormalBannerPage()),
              ('Collapsible anchored banner', CollapsibleBannerPage()),
              ('Collapsible banner (top)', CollapsibleTopBannerPage()),
              ('Inline adaptive banner (scrolling)', InlineBannerPage()),
              ('Fixed-size banner', FixedBannerPage()),
              ('Native ads (small and medium)', NativeAdsPage()),
            ])
              ListTile(
                title: Text(page.$1),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: (_) => page.$2)),
              ),
            const SizedBox(height: 20),
            const NativeAdsContainer(index: 0, size: NativeAdsSize.small),
            TextButton(
              onPressed: () =>
                  AdsManager.instance.retryFailedAds(unit: AdsUnit.native),
              child: const Text('Retry failed native ad'),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class NormalBannerPage extends StatelessWidget {
  const NormalBannerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Normal banner')),
      body: Center(
        child: TextButton(
          onPressed: () =>
              AdsManager.instance.retryFailedAds(unit: AdsUnit.banner),
          child: const Text('Retry failed banners'),
        ),
      ),
      bottomNavigationBar: const SafeArea(
        child: BannerAdContainer(index: 0, type: BannerAdsType.normal),
      ),
    );
  }
}

class CollapsibleBannerPage extends StatelessWidget {
  const CollapsibleBannerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Collapsible banner')),
      body: const Center(child: Text('Content')),
      bottomNavigationBar: const SafeArea(
        child: BannerAdContainer(
          index: 0,
          type: BannerAdsType.collapsible,
          collapsiblePlacement: BannerCollapsiblePlacement.bottom,
        ),
      ),
    );
  }
}

class CollapsibleTopBannerPage extends StatelessWidget {
  const CollapsibleTopBannerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Collapsible banner (top)')),
      body: const Column(
        children: [
          BannerAdContainer(
            index: 0,
            type: BannerAdsType.collapsible,
            collapsiblePlacement: BannerCollapsiblePlacement.top,
          ),
          Expanded(child: Center(child: Text('Content'))),
        ],
      ),
    );
  }
}

class InlineBannerPage extends StatelessWidget {
  const InlineBannerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inline adaptive banner')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 20,
        itemBuilder: (context, i) => i == 5
            ? const BannerAdContainer(
                index: 0,
                type: BannerAdsType.inlineAdaptive,
                maxHeight: 250,
              )
            : ListTile(title: Text('Item $i')),
      ),
    );
  }
}

class NativeAdsPage extends StatelessWidget {
  const NativeAdsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Native ads')),
      body: ListView(
        children: const [
          NativeAdsContainer(index: 0, size: NativeAdsSize.small),
          SizedBox(height: 24),
          NativeAdsContainer(index: 0, size: NativeAdsSize.medium),
          SizedBox(height: 24),
        ],
      ),
    );
  }
}

class FixedBannerPage extends StatelessWidget {
  const FixedBannerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fixed-size banner')),
      body: const Align(
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 16),
            BannerAdContainer(
              index: 0,
              type: BannerAdsType.fixed,
              size: BannerAdsSize.banner,
            ),
            SizedBox(height: 16),
            BannerAdContainer(
              index: 0,
              type: BannerAdsType.fixed,
              size: BannerAdsSize.mediumRectangle,
            ),
          ],
        ),
      ),
    );
  }
}
