abstract final class DanmakuBackendPolicy {
  static bool usesBuiltIn({
    required bool isWindows,
    required String endpoint,
    required String appId,
    required String appSecret,
  }) =>
      !isWindows &&
      endpoint.trim().isEmpty &&
      appId.trim().isEmpty &&
      appSecret.trim().isEmpty;
}
