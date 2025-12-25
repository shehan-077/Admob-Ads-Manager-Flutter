# Custom AdMob Ads Manager Library (Flutter)

Easily integrate Google AdMob into your flutter project with just a few lines of code.

---

## 🚀 Key Features

- Pre-load ads for a seamless user experience.
- Built-in loading screen with customizable color - shown automatically during the ad load.
- No need to manually provide AdMob test ad units — just set `AdsStatus.TESTING` to use predefined test ads.
- Automatically shows **test ads in debug builds** and **real ads in release builds** with `AdsStatus.HYBRID`

---

## 📺 Supported Ad Types

- Interstitial Ads
- App Open Ads
- Rewarded Ads
- Rewarded Interstitial Ads
- Native Ads (Small & Medium)
- Banner Ads

---

## 🧩 Getting Started

### Step 1: Add Plugin

Add the following to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_admob_ads_manager:
    git:
      url: https://github.com/your-org/flutter_admob_ads_manager.git
      ref: 1.0.0
```

---

## 🔧 1. Define Ads Units

### With Single Ad Unit ID

```dart
  final ids = AdMobIds.single(
    appId: "appId",
    interstitialId: "interstitialId",
    bannerId: "bannerId",
    appOpenId: "appOpenId",
    rewardedId: "rewardedId",
    nativeId: "nativeId",
    rewardedIntId: "rewardedIntId",
  );
```

- `appId`: admob app id
- `interstitialId`: interstitial ad unit id
- `bannerId`: banner ad unit id
- `appOpenId`: app open ad unit id
- `rewardedId`: reward ad unit id
- `nativeId`: native ad unit id
- `rewardedIntId`: reward interstitial ad unit id

---

## 🧠 2. Initialize AdsManager

```dart
  await AdsManager.instance.init(
    ids: ids,
    status: AdsStatus.testing,
    loadingColor: Colors.black,
  );
```

- `ids`: Initialized ads unit.
- `status`: Ads manager status. (enabled, disabled, testing, hybrid)
- `loadingColor`: Ads loading background color.

---

## ⚡ Pre-load Ads

```dart
// Pre-load Interstitial Ad at index 0
await AdsManager.instance.preLoad(AdsUnit.interstitial, 0);

// Pre-load Rewarded Ad at index 0
await AdsManager.instance.preLoad(AdsUnit.reward, 0);

// Pre-load Rewarded Interstitial Ad at index 0
await AdsManager.instance.preLoad(AdsUnit.rewardInt, 0);
```

---

## 🧩 Complete Example

```dart
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
    loadingColor: Colors.black,
  );

  await AdsManager.instance.preLoad(AdsUnit.interstitial, 0);
```

---

## ▶️ Show Ads

### App Open Ad

```dart
AdsManager.instance.showAppOpen(context, 0, _SimpleRequestHandler());

class _SimpleRequestHandler implements RequestHandler {
  @override
  void onError(String error) {
    debugPrint('App Open error: $error');
  }

  @override
  void onSuccess() {
    debugPrint('App Open success / dismissed');
  }
}
```

### Interstitial Ad

```dart
AdsManager.instance.showInterstitial(context, 0, _SimpleRequestHandler());

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
```

### Rewarded Ad

```dart
AdsManager.instance.showRewarded(context, 0, _SimpleRewardHandler());

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
```

### Rewarded Interstitial Ad

```dart
AdsManager.instance.showRewardedInterstitial(context, 0, _SimpleRewardHandler());

class _SimpleRewardHandler implements RewardedRequestHandler {
  @override
  void onDismissed() {
    debugPrint('Reward Int dismissed');
  }

  @override
  void onError(String error) {
    debugPrint('Reward Int error: $error');
  }

  @override
  void onFailedToShow(String error) {
    debugPrint('Reward Int failed to show: $error');
  }

  @override
  void onRewarded() {
    debugPrint('User rewarded!');
  }

  @override
  void onShowed() {
    debugPrint('Reward Int showed');
  }
}
```

### Banner Ad

```dart
const BannerAdContainer(index: 0);
```

### Native Ad (Small)

```dart
const NativeAdsContainer(index: 0, size: NativeAdsSize.small);
```

### Native Ad (Medium)

```dart
const NativeAdsContainer(index: 0, size: NativeAdsSize.medium);
```

---

## 💡 Usage Tips

- Always preload ads to reduce display delay (Interstitial, Reward, and Reward Interstitial Ads only).
- Handle all ad events for reliability.
- Follow AdMob policy strictly to avoid account issues.
- Use `AdsStatus.HYBRID` during development - Ads manager shows testing ads and after production, ads will automatically switch to real ad units defined by you.

---

## 🎉 Enjoy!

Feel free to use this library to simplify and streamline AdMob integration.
