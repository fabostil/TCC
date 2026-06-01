import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../voice_realtime_event_bus.dart';
import '../../voice_realtime_events.dart';
import 'voice_foreground_service.dart';

abstract class ForegroundTaskClient {
  void init({
    required AndroidNotificationOptions androidNotificationOptions,
    required IOSNotificationOptions iosNotificationOptions,
    required ForegroundTaskOptions foregroundTaskOptions,
  });

  Future<ServiceRequestResult> startService({
    required String notificationTitle,
    required String notificationText,
    List<ForegroundServiceTypes>? serviceTypes,
  });

  Future<ServiceRequestResult> updateService({
    required String notificationTitle,
    required String notificationText,
  });

  Future<ServiceRequestResult> stopService();
}

class PluginForegroundTaskClient implements ForegroundTaskClient {
  const PluginForegroundTaskClient();

  @override
  void init({
    required AndroidNotificationOptions androidNotificationOptions,
    required IOSNotificationOptions iosNotificationOptions,
    required ForegroundTaskOptions foregroundTaskOptions,
  }) {
    FlutterForegroundTask.init(
      androidNotificationOptions: androidNotificationOptions,
      iosNotificationOptions: iosNotificationOptions,
      foregroundTaskOptions: foregroundTaskOptions,
    );
  }

  @override
  Future<ServiceRequestResult> startService({
    required String notificationTitle,
    required String notificationText,
    List<ForegroundServiceTypes>? serviceTypes,
  }) {
    return FlutterForegroundTask.startService(
      notificationTitle: notificationTitle,
      notificationText: notificationText,
      serviceTypes: serviceTypes,
    );
  }

  @override
  Future<ServiceRequestResult> updateService({
    required String notificationTitle,
    required String notificationText,
  }) {
    return FlutterForegroundTask.updateService(
      notificationTitle: notificationTitle,
      notificationText: notificationText,
    );
  }

  @override
  Future<ServiceRequestResult> stopService() {
    return FlutterForegroundTask.stopService();
  }
}

class AndroidVoiceForegroundService implements VoiceForegroundService {
  AndroidVoiceForegroundService({
    VoiceRealtimeEventBus? eventBus,
    ForegroundTaskClient? foregroundTaskClient,
    Future<bool> Function()? notificationPermissionRequester,
  }) : eventBus = eventBus ?? VoiceRealtimeEventBus.instance,
       _foregroundTaskClient =
           foregroundTaskClient ?? const PluginForegroundTaskClient(),
       _notificationPermissionRequester =
           notificationPermissionRequester ??
           _requestNotificationPermissionIfNeeded;

  static const String notificationTitle = 'Assistente Musical';
  static const String notificationMessage =
      'Escuta hands-free ligada — Pronto para comandos';
  static const String _channelId = 'voice_assistant_channel';
  static const String _channelName = 'Assistente Musical';
  static const String _correlationId = 'foreground_service';

  final VoiceRealtimeEventBus eventBus;
  final ForegroundTaskClient _foregroundTaskClient;
  final Future<bool> Function() _notificationPermissionRequester;

  var _initialized = false;
  var _started = false;
  var _startInFlight = false;

  bool get isInitialized => _initialized;
  bool get isStarted => _started;

  @override
  Future<void> startService({
    required String title,
    required String message,
  }) async {
    if (_started || _startInFlight) {
      return;
    }

    _startInFlight = true;
    try {
      final notificationGranted = await _notificationPermissionRequester();
      if (!notificationGranted) {
        eventBus.publish(
          VoiceSystemDegradedEvent(
            source: 'android_voice_foreground_service',
            reason: 'android_notification_permission_denied',
            correlationId: _correlationId,
          ),
        );
      }

      _ensureInitialized();
      final result = await _foregroundTaskClient.startService(
        notificationTitle: notificationTitle,
        notificationText: notificationMessage,
        serviceTypes: const [ForegroundServiceTypes.microphone],
      );

      if (result is ServiceRequestFailure) {
        if (result.error is ServiceAlreadyStartedException) {
          _started = true;
          _publishStarted(
            requestedTitle: title,
            requestedMessage: message,
            alreadyRunning: true,
          );
          return;
        }
        _publishFailure(
          'android_foreground_service_start_failed',
          result.error,
        );
        return;
      }

      _started = true;
      _publishStarted(
        requestedTitle: title,
        requestedMessage: message,
        alreadyRunning: false,
      );
    } catch (error) {
      _publishFailure('android_foreground_service_start_failed', error);
    } finally {
      _startInFlight = false;
    }
  }

  @override
  Future<void> updateMessage(String message) async {
    if (!_started) {
      eventBus.publish(
        VoiceSystemDegradedEvent(
          source: 'android_voice_foreground_service',
          reason: 'android_foreground_service_update_before_start',
          correlationId: _correlationId,
        ),
      );
      return;
    }

    final effectiveMessage = message.trim().isEmpty
        ? notificationMessage
        : message;
    try {
      final result = await _foregroundTaskClient.updateService(
        notificationTitle: notificationTitle,
        notificationText: effectiveMessage,
      );

      if (result is ServiceRequestFailure) {
        _publishFailure(
          'android_foreground_service_update_failed',
          result.error,
        );
        return;
      }

      eventBus.publish(
        VoiceStateChangedEvent(
          source: 'android_voice_foreground_service',
          previousState: 'foregroundStarted',
          nextState: 'foregroundStarted',
          reason: 'android_foreground_service_updated',
          correlationId: _correlationId,
          metadata: {'message': effectiveMessage},
        ),
      );
    } catch (error) {
      _publishFailure('android_foreground_service_update_failed', error);
    }
  }

  @override
  Future<void> stopService() async {
    if (!_started && !_startInFlight) {
      return;
    }

    try {
      final result = await _foregroundTaskClient.stopService();
      if (result is ServiceRequestFailure) {
        if (result.error is ServiceNotStartedException) {
          return;
        }
        _publishFailure('android_foreground_service_stop_failed', result.error);
        return;
      }

      eventBus.publish(
        VoiceStateChangedEvent(
          source: 'android_voice_foreground_service',
          previousState: 'foregroundStarted',
          nextState: 'foregroundStopped',
          reason: 'android_foreground_service_stopped',
          correlationId: _correlationId,
        ),
      );
    } catch (error) {
      _publishFailure('android_foreground_service_stop_failed', error);
    } finally {
      _started = false;
      _startInFlight = false;
    }
  }

  void _publishStarted({
    required String requestedTitle,
    required String requestedMessage,
    required bool alreadyRunning,
  }) {
    eventBus.publish(
      VoiceStateChangedEvent(
        source: 'android_voice_foreground_service',
        previousState: 'foregroundStopped',
        nextState: 'foregroundStarted',
        reason: 'android_foreground_service_started',
        correlationId: _correlationId,
        metadata: {
          'title': notificationTitle,
          'message': notificationMessage,
          'foregroundServiceType': 'microphone',
          'requestedTitle': requestedTitle,
          'requestedMessage': requestedMessage,
          'alreadyRunning': alreadyRunning,
        },
      ),
    );
  }

  void _ensureInitialized() {
    if (_initialized) {
      return;
    }

    _foregroundTaskClient.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _channelId,
        channelName: _channelName,
        channelImportance: NotificationChannelImportance.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowAutoRestart: true,
        stopWithTask: false,
      ),
    );
    _initialized = true;
  }

  void _publishFailure(String reason, Object error) {
    eventBus.publish(
      VoiceSystemDegradedEvent(
        source: 'android_voice_foreground_service',
        reason: reason,
        correlationId: _correlationId,
        metadata: {'error': error.toString()},
      ),
    );
  }

  static Future<bool> _requestNotificationPermissionIfNeeded() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }

    final status = await Permission.notification.request();
    return status.isGranted;
  }
}
