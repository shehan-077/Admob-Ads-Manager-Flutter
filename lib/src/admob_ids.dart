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
  });

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
}
