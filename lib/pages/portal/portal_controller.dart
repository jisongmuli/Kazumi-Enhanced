import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/portal/portal_catalog.dart';
import 'package:kazumi/pages/portal/portal_models.dart';

class PortalController extends ChangeNotifier {
  PortalController({required this.channel, required this.catalog})
    : category = switch (channel) {
        PortalChannel.home => PortalCategory.recommend,
        PortalChannel.anime => PortalCategory.anime,
        PortalChannel.cinema => PortalCategory.cinema,
        PortalChannel.shorts => PortalCategory.shorts,
        PortalChannel.youtube => PortalCategory.youtube,
      };
  final PortalChannel channel;
  final PortalCatalog catalog;
  PortalCategory category;
  String keyword = '';
  bool initialized = false;
  double scrollOffset = 0;
  int scrollReset = 0;
  void resetScroll() {
    scrollOffset = 0;
    ++scrollReset;
    notifyListeners();
  }

  final groups = <PortalCategory, PortalListing>{};
  final errors = <PortalCategory, String>{};
  final pending = <PortalCategory>{};
  final loadingMore = <PortalCategory>{};
  int _generation = 0;
  bool _disposed = false;
  CancelToken? _cancel;
  bool get loading => pending.isNotEmpty;
  bool get isLanding => keyword.isEmpty && category == PortalCategory.recommend;
  List<PortalItem> get items {
    final unique = <String, PortalItem>{};
    final lists = [
      for (final target in targets) groups[target]?.items ?? <PortalItem>[],
    ];
    final longest = lists.fold<int>(0, (n, l) => l.length > n ? l.length : n);
    for (var i = 0; i < longest; i++) {
      for (final list in lists) {
        if (i < list.length) unique.putIfAbsent(list[i].key, () => list[i]);
      }
    }
    return unique.values.toList();
  }

  List<PortalCategory> get targets =>
      category == PortalCategory.recommend || category == PortalCategory.all
      ? [
          PortalCategory.anime,
          PortalCategory.cinema,
          PortalCategory.shorts,
          PortalCategory.youtube,
        ]
      : [category];

  Future<void> load({
    PortalCategory? category,
    String? keyword,
    bool refresh = false,
  }) async {
    final generation = ++_generation;
    ++scrollReset;
    _cancel?.cancel();
    final token = CancelToken();
    _cancel = token;
    if (category != null) this.category = category;
    if (keyword != null) this.keyword = keyword.trim();
    groups.clear();
    errors.clear();
    loadingMore.clear();
    pending.clear();
    final query = this.keyword;
    pending.addAll(targets);
    initialized = true;
    notifyListeners();
    await Future.wait(
      targets.map(
        (target) => _fetch(target, generation, token, query, refresh),
      ),
    );
  }

  Future<void> _fetch(
    PortalCategory target,
    int generation,
    CancelToken token,
    String query,
    bool refresh, {
    String? next,
  }) async {
    try {
      final result = await catalog.fetch(
        target,
        keyword: query,
        next: next,
        refresh: refresh,
        cancelToken: token,
      );
      if (_disposed || generation != _generation) return;
      if (next == null) {
        groups[target] = result;
      } else {
        final unique = {
          for (final item in [...?groups[target]?.items, ...result.items])
            item.key: item,
        };
        groups[target] = PortalListing(
          unique.values.toList(),
          next: result.next,
        );
      }
      errors.remove(target);
    } catch (error) {
      if (_disposed || generation != _generation) return;
      errors[target] = error is StateError ? error.message : '连接失败或超时，请检查网络后重试';
    } finally {
      if (!_disposed && generation == _generation) {
        pending.remove(target);
        loadingMore.remove(target);
        notifyListeners();
      }
    }
  }

  Future<void> retry(PortalCategory target) async {
    if (_disposed || pending.contains(target)) return;
    pending.add(target);
    errors.remove(target);
    notifyListeners();
    await _fetch(target, _generation, _cancel ??= CancelToken(), keyword, true);
  }

  Future<void> loadMore(PortalCategory target) async {
    final next = groups[target]?.next;
    if (next == null ||
        pending.contains(target) ||
        loadingMore.contains(target)) {
      return;
    }
    loadingMore.add(target);
    notifyListeners();
    await _fetch(
      target,
      _generation,
      _cancel ??= CancelToken(),
      keyword,
      false,
      next: next,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _cancel?.cancel();
    super.dispose();
  }
}

class PortalHub implements Disposable {
  final PortalCatalog catalog = LivePortalCatalog();
  final _controllers = <PortalChannel, PortalController>{};
  PortalController forChannel(PortalChannel channel) =>
      _controllers.putIfAbsent(
        channel,
        () => PortalController(channel: channel, catalog: catalog),
      );
  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
  }
}
