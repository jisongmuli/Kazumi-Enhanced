import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/cinema/cinema_controller.dart';
import 'package:kazumi/pages/cinema/cinema_page.dart';
import 'package:kazumi/pages/portal/portal_module.dart';
import 'package:kazumi/pages/portal/portal_models.dart';

final cinemaModule = createModule(
  path: '/cinema',
  register: (c) {
    c.route(
      '/',
      transition: TransitionType.none,
      child: (context, state) => portalPage(PortalChannel.cinema),
    );
    c.route(
      '/library',
      transition: TransitionType.none,
      child: (context, state) =>
          CinemaPage(controller: inject<CinemaController>()),
    );
  },
);
