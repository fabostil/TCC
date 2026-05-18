import 'package:flutter/material.dart';

import 'voice_listening_coordinator.dart';

/// Cancela STT ao empilhar rotas e invalida reinícios ao desempilhar.
class VoiceRouteObserver extends RouteObserver<PageRoute<dynamic>> {
  final VoiceListeningCoordinator _coordinator =
      VoiceListeningCoordinator.instance;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (route is PageRoute) {
      _coordinator.onRouteDidPush();
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (route is PageRoute) {
      _coordinator.onRouteDidPop();
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (oldRoute is PageRoute) {
      _coordinator.onRouteDidPush();
    }
  }
}
