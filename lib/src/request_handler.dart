import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

typedef ErrorCallback = void Function(Object error);
typedef RewardEarnedCallback = void Function(RewardItem reward);

abstract class RequestHandler {
  void onSuccess() {}
  void onError(String error) {}
}

class RequestHandlerImpl extends RequestHandler {
  final VoidCallback? _success;
  final void Function(String error)? _error;

  RequestHandlerImpl({
    VoidCallback? onSuccess,
    void Function(String error)? onError,
  }) : _success = onSuccess,
       _error = onError;

  @override
  void onSuccess() => _success?.call();

  @override
  void onError(String error) => _error?.call(error);
}

class RewardedCallbacks {
  final VoidCallback? onLoaded;
  final VoidCallback? onShowed;
  final RewardEarnedCallback? onRewarded;
  final VoidCallback? onDismissed;
  final ErrorCallback? onError;
  final ErrorCallback? onFailedToShow;
  final ErrorCallback? onFailedToLoad;

  const RewardedCallbacks({
    this.onLoaded,
    this.onShowed,
    this.onRewarded,
    this.onDismissed,
    this.onError,
    this.onFailedToShow,
    this.onFailedToLoad,
  });
}

class RewardedHandlerBuilder {
  VoidCallback? _onLoaded;
  VoidCallback? _onShowed;
  RewardEarnedCallback? _onRewarded;
  VoidCallback? _onDismissed;
  ErrorCallback? _onError;
  ErrorCallback? _onFailedToShow;

  RewardedHandlerBuilder onLoaded(VoidCallback cb) {
    _onLoaded = cb;
    return this;
  }

  RewardedHandlerBuilder onShowed(VoidCallback cb) {
    _onShowed = cb;
    return this;
  }

  RewardedHandlerBuilder onRewarded(RewardEarnedCallback cb) {
    _onRewarded = cb;
    return this;
  }

  RewardedHandlerBuilder onDismissed(VoidCallback cb) {
    _onDismissed = cb;
    return this;
  }

  RewardedHandlerBuilder onError(ErrorCallback cb) {
    _onError = cb;
    return this;
  }

  RewardedHandlerBuilder onFailedToShow(ErrorCallback cb) {
    _onFailedToShow = cb;
    return this;
  }

  RewardedCallbacks build() {
    return RewardedCallbacks(
      onLoaded: _onLoaded,
      onShowed: _onShowed,
      onRewarded: _onRewarded,
      onDismissed: _onDismissed,
      onError: _onError,
      onFailedToShow: _onFailedToShow,
    );
  }
}
