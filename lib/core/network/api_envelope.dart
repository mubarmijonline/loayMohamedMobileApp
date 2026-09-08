/// Standard server response envelope:
/// { "success": bool, "data": ..., "error": { code, message, details } }
class ApiEnvelope<T> {
  const ApiEnvelope({
    required this.success,
    this.data,
    this.errorCode,
    this.errorMessage,
    this.errorDetails,
  });

  final bool success;
  final T? data;
  final String? errorCode;
  final String? errorMessage;
  final Object? errorDetails;

  static ApiEnvelope<T> from<T>(
    Object? body,
    T Function(Object json) parser,
  ) {
    if (body is! Map) {
      // Backward compatibility — backend sometimes returns a raw payload.
      return ApiEnvelope<T>(
          success: true, data: body == null ? null : parser(body));
    }
    final hasEnvelope = body.containsKey('success') &&
        (body.containsKey('data') || body.containsKey('error'));
    if (!hasEnvelope) {
      return ApiEnvelope<T>(success: true, data: parser(body));
    }
    final ok = body['success'] == true;
    final data = body['data'];
    final err = body['error'];
    return ApiEnvelope<T>(
      success: ok,
      data: ok && data != null ? parser(data as Object) : null,
      errorCode: err is Map ? err['code']?.toString() : null,
      errorMessage: err is Map ? err['message']?.toString() : null,
      errorDetails: err is Map ? err['details'] : null,
    );
  }
}
