class PlaybackNetworkPolicy {
  const PlaybackNetworkPolicy._();

  // media_kit defaults to five seconds, including slow TLS connections.
  static const networkTimeout = '20';
  static const reconnectOptions =
      'reconnect=1,reconnect_on_network_error=1,reconnect_streamed=1,'
      'reconnect_on_http_error=5xx,reconnect_delay_max=5,'
      'reconnect_max_retries=3,reconnect_delay_total_max=15';

  static Future<void> apply({
    required String url,
    required bool isLocalPlayback,
    required int bufferSize,
    required bool Function() isCurrent,
    required Future<void> Function(String, String) setProperty,
    required Future<void> Function(List<String>) command,
  }) async {
    final uri = Uri.tryParse(url);
    if (isLocalPlayback ||
        uri == null ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        !isCurrent()) {
      return;
    }
    await setProperty('network-timeout', networkTimeout);
    if (!isCurrent()) return;
    // Avoid repeatedly exhausting a one-second buffer on large HLS segments.
    // A small memory budget must not wait for more data than it can hold.
    final prebuffer = bufferSize >= 16 * 1024 * 1024;
    await setProperty('cache-pause-wait', prebuffer ? '6' : '1');
    if (!isCurrent()) return;
    await setProperty('cache-pause-initial', prebuffer ? 'yes' : 'no');
    if (!isCurrent()) return;
    // mpv's custom HLS I/O opens segments through its stream layer, so apply
    // retries there, including connections nested beneath AES encryption.
    // change-list append takes one key/value pair, not a comma-separated list.
    for (final option in reconnectOptions.split(',')) {
      await command(['change-list', 'stream-lavf-o', 'append', option]);
      if (!isCurrent()) return;
    }
    // Enable one-segment lookahead when custom I/O disables auto-detection.
    // Append to retain media_kit's ad filter and protocol whitelist settings.
    await command([
      'change-list',
      'demuxer-lavf-o',
      'append',
      'http_multiple=1',
    ]);
  }
}
