import 'ads_unit.dart';

/// What happened to an ad. See [AdEvent].
enum AdEventType {
  /// A load was started.
  request,

  /// A load succeeded.
  loaded,

  /// A load failed; [AdEvent.errorCode] holds the SDK error code when known.
  failed,

  /// The ad was shown: a full-screen ad started presenting, or a banner /
  /// native ad recorded its impression.
  shown,

  /// The SDK reported estimated revenue for an impression (`onPaidEvent`).
  paid,
}

/// One observation about an ad, delivered to [AdsManager.onAdEvent].
///
/// Contains no personal data: only the format, slot, error code and the
/// revenue figures the SDK reports.
class AdEvent {
  const AdEvent({
    required this.type,
    required this.unit,
    required this.index,
    this.errorCode,
    this.errorMessage,
    this.valueMicros,
    this.currencyCode,
    this.precision,
  });

  final AdEventType type;
  final AdsUnit unit;
  final int index;

  /// `LoadAdError.code` for [AdEventType.failed] (null for timeouts and
  /// errors that did not come from the SDK).
  final int? errorCode;
  final String? errorMessage;

  /// Revenue in millionths of [currencyCode] ([AdEventType.paid] only).
  final double? valueMicros;
  final String? currencyCode;

  /// `PrecisionType.name` of the revenue figure ([AdEventType.paid] only).
  final String? precision;

  @override
  String toString() =>
      'AdEvent(${type.name} ${unit.name}#$index'
      '${errorCode != null ? ' code=$errorCode' : ''}'
      '${valueMicros != null ? ' micros=$valueMicros $currencyCode' : ''})';
}

/// How a load requested through `AdsManager.preLoadWithResult` ended.
enum AdLoadOutcome {
  /// An ad is cached and ready (loaded now or already cached).
  loaded,

  /// The load failed (no fill, network, timeout, consent withdrawn...).
  failed,

  /// Ads cannot be requested yet (consent running or not granted); the intent
  /// is remembered and runs once ads become available.
  deferred,

  /// Ads are disabled, or the format has no full-screen cache (banner,
  /// native).
  unavailable,
}

class AdLoadResult {
  const AdLoadResult(this.outcome, {this.errorCode, this.message});

  final AdLoadOutcome outcome;
  final int? errorCode;
  final String? message;

  bool get isLoaded => outcome == AdLoadOutcome.loaded;

  @override
  String toString() =>
      'AdLoadResult(${outcome.name}'
      '${errorCode != null ? ' code=$errorCode' : ''})';
}
