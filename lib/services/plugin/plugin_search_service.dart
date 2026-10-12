import 'dart:async';
import 'package:dio/dio.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/pages/info/info_controller.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:kazumi/utils/async_session.dart';

class PluginSearchService {
  PluginSearchService({
    required this.infoController,
    required this.pluginsController,
    this.maxConcurrent = 6,
    this.queryTimeout = const Duration(seconds: 40),
  }) : assert(maxConcurrent > 0);

  final InfoController infoController;
  final PluginsController pluginsController;
  final int maxConcurrent;
  final Duration queryTimeout;
  final Map<String, RuleCancelToken> _requestTokens = {};

  /// Per-plugin sessions so a replacement query (alias/manual search)
  /// invalidates the write-back of the still-running previous one.
  final Map<String, AsyncSessionOwner> _querySessions = {};
  bool _isCancelled = false;

  Future<void> querySource(String keyword, String pluginName) async {
    if (_isCancelled) return;
    for (final plugin in pluginsController.pluginList) {
      if (plugin.name == pluginName) {
        infoController.pluginSearchResponseList.removeWhere(
          (response) => response.pluginName == pluginName,
        );
        infoController.pluginSearchErrors.remove(pluginName);
        infoController.pluginSearchStatus[pluginName] =
            PluginSearchStatus.pending;
        await _queryPlugin(plugin, keyword, _beginQuery(pluginName));
        return;
      }
    }
  }

  /// Publishes the result page harvested by the captcha webview, skipping
  /// one network round trip. Returns false when the HTML does not parse
  /// into results; callers should fall back to [querySource].
  bool applyHarvestedSearchResult(String pluginName, String html) {
    if (_isCancelled) return false;
    for (final plugin in pluginsController.pluginList) {
      if (plugin.name != pluginName) continue;
      final result = plugin.parseHarvestedSearch(html);
      if (result == null) return false;
      _beginQuery(pluginName);
      infoController.pluginSearchErrors.remove(pluginName);
      infoController.pluginSearchResponseList.removeWhere(
        (response) => response.pluginName == pluginName,
      );
      infoController.pluginSearchStatus[pluginName] =
          PluginSearchStatus.success;
      pluginsController.validityTracker.markSearchValid(pluginName);
      infoController.pluginSearchResponseList.add(result);
      return true;
    }
    return false;
  }

  Future<void> queryAllSource(String keyword) async {
    if (_isCancelled) return;
    infoController.pluginSearchResponseList.clear();
    infoController.pluginSearchStatus.clear();
    infoController.pluginSearchErrors.clear();

    final plugins = pluginsController.pluginList.toList();
    // Capture sessions when enqueued: a manual query must supersede a queued
    // bulk query as well as one already in flight.
    final sessions = {
      for (final plugin in plugins) plugin.name: _beginQuery(plugin.name),
    };
    for (final plugin in plugins) {
      infoController.pluginSearchStatus[plugin.name] =
          PluginSearchStatus.pending;
    }
    var index = 0;
    Future<void> worker() async {
      while (!_isCancelled && index < plugins.length) {
        final plugin = plugins[index++];
        await _queryPlugin(plugin, keyword, sessions[plugin.name]!);
      }
    }

    await Future.wait(
      List.generate(
        plugins.length < maxConcurrent ? plugins.length : maxConcurrent,
        (_) => worker(),
      ),
    );
  }

  AsyncSession _beginQuery(String name) {
    _requestTokens.remove(name)?.cancel('查询已替换');
    return _querySessions.putIfAbsent(name, AsyncSessionOwner.new).begin();
  }

  Future<void> _queryPlugin(
    Plugin plugin,
    String keyword,
    AsyncSession session,
  ) async {
    if (_isCancelled || session.isStale) return;
    final token = RuleCancelToken();
    _requestTokens[plugin.name] = token;
    try {
      final result = await plugin
          .queryBangumi(keyword, shouldRethrow: true, cancelToken: token)
          .timeout(
            queryTimeout,
            onTimeout: () {
              token.cancel('片源检索超时');
              throw TimeoutException('片源检索超时');
            },
          );
      if (_isCancelled || session.isStale) return;
      infoController.pluginSearchStatus[plugin.name] =
          PluginSearchStatus.success;
      if (result.data.isNotEmpty) {
        pluginsController.validityTracker.markSearchValid(plugin.name);
      }
      infoController.pluginSearchResponseList.add(result);
    } catch (error) {
      if (_isCancelled || session.isStale) return;
      _handleSearchError(plugin, error);
    } finally {
      if (identical(_requestTokens[plugin.name], token)) {
        _requestTokens.remove(plugin.name);
      }
    }
  }

  void _handleSearchError(Plugin plugin, Object error) {
    if (error is CaptchaRequiredException) {
      KazumiLogger().i(
        'PluginSearchService: captcha required for ${error.pluginName}',
      );
      infoController.pluginSearchStatus[error.pluginName] =
          PluginSearchStatus.captcha;
      return;
    }
    if (error is NoResultException) {
      KazumiLogger().i(
        'PluginSearchService: no results for ${error.pluginName}',
      );
      infoController.pluginSearchStatus[error.pluginName] =
          PluginSearchStatus.noResult;
      return;
    }
    final name = error is SearchErrorException ? error.pluginName : plugin.name;
    final cause = error is SearchErrorException ? error.cause : error;
    infoController.pluginSearchErrors[name] = switch (cause) {
      TimeoutException() => '请求超时，请重试或选择其他来源',
      StateError() => cause.message,
      DioException(
        type: DioExceptionType.badResponse,
        response: final response,
      ) =>
        '网站返回 HTTP ${response?.statusCode ?? "错误"}，可打开原站检查',
      DioException(
        type: DioExceptionType.connectionTimeout ||
            DioExceptionType.receiveTimeout ||
            DioExceptionType.sendTimeout,
      ) =>
        '连接超时，请重试或选择其他来源',
      DioException(type: DioExceptionType.badCertificate) =>
        '该网站的证书无法验证，可打开原站检查',
      _ => '连接失败或页面无法解析，可重试或打开原站检查',
    };
    KazumiLogger().w('PluginSearchService: search error for $name');
    infoController.pluginSearchStatus[name] = PluginSearchStatus.error;
  }

  void cancel() {
    _isCancelled = true;
    for (final token in _requestTokens.values) {
      token.cancel('播放来源已关闭');
    }
    _requestTokens.clear();
    for (final owner in _querySessions.values) {
      owner.close();
    }
  }
}
