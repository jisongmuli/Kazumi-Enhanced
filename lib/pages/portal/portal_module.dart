import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/portal/portal_controller.dart';
import 'package:kazumi/pages/portal/portal_models.dart';
import 'package:kazumi/pages/portal/portal_page.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/services/storage/storage.dart';

PortalPage portalPage(PortalChannel channel) => PortalPage(
  controller: inject<PortalHub>().forChannel(channel),
  historyRepository: inject<IHistoryRepository>(),
  showScore: GStorage.getSetting(SettingsKeys.showRating),
);

final homeModule = createModule(
  path: '/home',
  register: (c) {
    c.route(
      '/',
      transition: TransitionType.none,
      child: (_, _) => portalPage(PortalChannel.home),
    );
  },
);
final shortsModule = createModule(
  path: '/shorts',
  register: (c) {
    c.route(
      '/',
      transition: TransitionType.none,
      child: (_, _) => portalPage(PortalChannel.shorts),
    );
  },
);
final youtubeModule = createModule(
  path: '/youtube',
  register: (c) {
    c.route(
      '/',
      transition: TransitionType.none,
      child: (_, _) => portalPage(PortalChannel.youtube),
    );
  },
);
