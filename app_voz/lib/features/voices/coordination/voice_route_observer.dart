import 'package:flutter/material.dart';

import '../realtime/runtime/runtime_registry.dart';
import 'voice_listening_coordinator.dart';

/// Cancela STT ao empilhar rotas e invalida reinícios ao desempilhar.
class VoiceRouteObserver extends RouteObserver<PageRoute<dynamic>> {
  final VoiceListeningCoordinator _coordinator =
      VoiceListeningCoordinator.instance;
  final VoiceRuntimeRegistry _runtimeRegistry = VoiceRuntimeRegistry.instance;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (route is PageRoute) {
      _runtimeRegistry.registerRouteContext(
        routeId: route.settings.name ?? route.runtimeType.toString(),
        routeName: route.settings.name,
        metadata: {'action': 'push'},
      );
      _coordinator.onRouteDidPush();
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (route is PageRoute) {
      if (previousRoute is PageRoute) {
        _runtimeRegistry.registerRouteContext(
          routeId:
              previousRoute.settings.name ??
              previousRoute.runtimeType.toString(),
          routeName: previousRoute.settings.name,
          metadata: {'action': 'pop'},
        );
      } else {
        _runtimeRegistry.clearRouteContext();
      }
      _coordinator.onRouteDidPop();
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (oldRoute is PageRoute) {
      if (newRoute is PageRoute) {
        _runtimeRegistry.registerRouteContext(
          routeId: newRoute.settings.name ?? newRoute.runtimeType.toString(),
          routeName: newRoute.settings.name,
          metadata: {'action': 'replace'},
        );
      }
      _coordinator.onRouteDidPush();
    }
  }
}
