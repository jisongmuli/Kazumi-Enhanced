import 'dart:io';
import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/desktop_window_controls.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/menu/route_visibility.dart';
import 'package:kazumi/pages/router.dart';
import 'package:kazumi/pages/portal/portal_controller.dart';
import 'package:kazumi/pages/portal/portal_header.dart';
import 'package:kazumi/pages/portal/portal_models.dart';
import 'package:kazumi/pages/portal/portal_theme.dart';
import 'package:kazumi/services/platform/desktop_window_config.dart';
import 'package:kazumi/utils/device.dart';
import 'package:window_manager/window_manager.dart';

class ScaffoldMenu extends StatefulWidget {
  const ScaffoldMenu({super.key, required this.location});
  final String location;
  @override
  State<ScaffoldMenu> createState() => _ScaffoldMenu();
}

class _ScaffoldMenu extends State<ScaffoldMenu> with RouteAware {
  final _outletKey = GlobalKey<RouterOutletState>();
  late int _selectedIndex = menu.indexForPath(widget.location);
  DateTime? _lastExitPromptAt;
  bool _isCovered = false;
  bool _inSourceLibrary = false;

  @override
  void didUpdateWidget(covariant ScaffoldMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      _selectedIndex = menu.indexForPath(widget.location);
      _inSourceLibrary = widget.location.contains('/cinema/library');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<void>) rootRouteObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    rootRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPushNext() => _setCovered(true);
  @override
  void didPopNext() => _setCovered(false);
  void _setCovered(bool value) {
    if (!mounted || _isCovered == value) return;
    setState(() => _isCovered = value);
  }

  void _selectDestination(int index, {bool resetHome = true}) {
    _lastExitPromptAt = null;
    if (index == 5 && resetHome) {
      final home = inject<PortalHub>().forChannel(PortalChannel.home);
      home.resetScroll();
      if (home.initialized &&
          (home.category != PortalCategory.recommend ||
              home.keyword.isNotEmpty)) {
        home.load(category: PortalCategory.recommend, keyword: '');
      }
    }
    if (index == _selectedIndex && !_inSourceLibrary) return;
    final outlet = _outletKey.currentState;
    if (outlet == null) return;
    outlet.navigate('/tab${menu.getPath(index)}/');
    setState(() {
      _selectedIndex = index;
      _inSourceLibrary = false;
    });
  }

  void _search(String keyword) {
    inject<PortalHub>()
        .forChannel(PortalChannel.home)
        .load(category: PortalCategory.all, keyword: keyword);
    _selectDestination(5, resetHome: false);
  }

  void _more(String value) {
    switch (value) {
      case 'timeline':
        _selectDestination(1);
      case 'collect':
        _selectDestination(2);
      case 'sources':
        _outletKey.currentState?.navigate('/tab/cinema/library');
        setState(() {
          _selectedIndex = 4;
          _inSourceLibrary = true;
        });
      case 'search':
        context.pushNamed('/search/');
      case 'settings':
        context.pushNamed('/settings/');
    }
  }

  void _handleSystemBack(BuildContext context) {
    if (_outletKey.currentState?.maybePop() ?? false) {
      _lastExitPromptAt = null;
      return;
    }
    if (_selectedIndex != 5) {
      _selectDestination(5);
      return;
    }
    final now = DateTime.now();
    if (_lastExitPromptAt == null ||
        now.difference(_lastExitPromptAt!) > const Duration(seconds: 2)) {
      _lastExitPromptAt = now;
      KazumiDialog.showToast(message: '再按一次退出应用', context: context);
      return;
    }
    _lastExitPromptAt = null;
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) => RouteVisibility(
    isCovered: _isCovered,
    child: Theme(
      data: PortalStyle.theme(Theme.of(context)),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _handleSystemBack(context);
        },
        child: Scaffold(
          backgroundColor: PortalStyle.background,
          body: Column(
            children: [
              PortalHeader(
                selectedIndex: _selectedIndex,
                onNavigate: _selectDestination,
                onSearch: _search,
                onHistory: () => context.pushNamed('/settings/history/'),
                onMore: _more,
                windowControls: Platform.isWindows
                    ? const DesktopWindowControls() : null,
                onClose: isDesktop() && !DesktopWindowConfig.showWindowButton
                    ? windowManager.close
                    : null,
              ),
              const Divider(height: 1, color: Color(0xffedf1f8)),
              Expanded(
                child: NotificationListener<NavigationNotification>(
                  onNotification: (notification) => !notification.canHandlePop,
                  child: RouterOutlet(key: _outletKey),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
