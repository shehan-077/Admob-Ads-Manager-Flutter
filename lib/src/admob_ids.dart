class AdMobIds {
  final String appId;
  final List<String> interstitialIds;
  final List<String> bannerIds;
  final List<String> appOpenIds;
  final List<String> rewardedIds;
  final List<String> nativeIds;
  final List<String> rewardedIntIds;

  const AdMobIds({
    required this.appId,
    required this.interstitialIds,
    required this.bannerIds,
    required this.appOpenIds,
    required this.rewardedIds,
    required this.nativeIds,
    required this.rewardedIntIds,
  }) : assert(interstitialIds.length > 0),
       assert(bannerIds.length > 0),
       assert(appOpenIds.length > 0),
       assert(rewardedIds.length > 0),
       assert(nativeIds.length > 0),
       assert(rewardedIntIds.length > 0);

  factory AdMobIds.single({
    required String appId,
    required String interstitialId,
    required String bannerId,
    required String appOpenId,
    required String rewardedId,
    required String nativeId,
    required String rewardedIntId,
  }) {
    return AdMobIds(
      appId: appId,
      interstitialIds: [interstitialId],
      bannerIds: [bannerId],
      appOpenIds: [appOpenId],
      rewardedIds: [rewardedId],
      nativeIds: [nativeId],
      rewardedIntIds: [rewardedIntId],
    );
  }

  String getInterstitial(int index) =>
      interstitialIds[index % interstitialIds.length];

  String getBanner(int index) => bannerIds[index % bannerIds.length];

  String getAppOpen(int index) => appOpenIds[index % appOpenIds.length];

  String getRewarded(int index) => rewardedIds[index % rewardedIds.length];

  String getNative(int index) => nativeIds[index % nativeIds.length];

  String getRewardedInterstitial(int index) =>
      rewardedIntIds[index % rewardedIntIds.length];
}
