import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/portal/portal_module.dart';
import 'package:kazumi/pages/portal/portal_models.dart';

final popularModule = createModule(
  path: '/popular',
  register: (c) {
    c.route(
      '/',
      transition: TransitionType.none,
      child: (context, state) => portalPage(PortalChannel.anime),
    );
  },
);
