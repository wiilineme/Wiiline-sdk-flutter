/// Thrown for any API response with `success: false`, or a network/transport
/// failure.
///
/// The API is not perfectly consistent about HTTP status codes (some failures
/// come back as HTTP 200 with `success: false`), so catch this exception
/// rather than branching on status codes alone.
class WiilineApiException implements Exception {
  WiilineApiException(
    this.message, {
    required this.status,
    this.code = 'unknown_error',
    this.details,
    this.retryAfter,
    this.body,
  });

  /// Human-readable message from the API (or the transport error).
  final String message;

  /// HTTP status code, or 0 for a network-level failure (no response).
  final int status;

  /// Short error code from the API's `error` field, e.g.
  /// `Insufficient balance`, `Renewal not available`, `eSIM not found`,
  /// or `timeout` / `network_error` for transport failures.
  final String code;

  /// Extra structured detail the API attached, if any.
  final Object? details;

  /// Seconds to wait before retrying - present on rate-limit (429) errors.
  final int? retryAfter;

  /// The raw parsed response body, if one was returned.
  final Map<String, dynamic>? body;

  /// True when nothing was charged because the request was rejected before
  /// payment (auth, validation, eligibility and balance errors).
  bool get isClientError => status >= 400 && status < 500;

  @override
  String toString() => 'WiilineApiException($status, $code): $message';
}
