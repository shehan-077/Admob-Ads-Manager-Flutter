typedef ErrorCallBack = void Function(String error);

abstract class RequestHandler {
  void onSuccess();
  void onError(String error);
}

abstract class RewardedRequestHandler {
  void onShowed();
  void onDismissed();
  void onRewarded();
  void onFailedToShow(String error);
  void onError(String error);
}
