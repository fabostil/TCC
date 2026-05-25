import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../voice_realtime_event_bus.dart';
import '../../voice_realtime_events.dart';
import 'voice_foreground_service.dart';

/// Android production foreground-service adapter.
///
/// This adapter uses a guarded platform channel and degrades through telemetry
/// when the native foreground-service channel is unavailable. Required Android
/// manifest entries for the real native service path:
///
/// - `android.permission.FOREGROUND_SERVICE`
/// - `android.permission.FOREGROUND_SERVICE_MICROPHONE`
/// - `android.permission.RECORD_AUDIO`
/// - `android.permission.POST_NOTIFICATIONS` requested at runtime on
///   Android 13+ before foreground notification startup.
/// - a foreground service declaration with `android:foregroundServiceType`
///   compatible with microphone capture.
class AndroidVoiceForegroundService implements VoiceForegroundService {
  AndroidVoiceForegroundService({
    VoiceRealtimeEventBus? eventBus,
    MethodChannel? channel,
    Future<bool> Function()? notificationPermissionRequester,
  }) : eventBus = eventBus ?? VoiceRealtimeEventBus.instance,
       _channel = channel ?? const MethodChannel(_channelName),
       _notificationPermissionRequester =
           notificationPermissionRequester ??
           _requestNotificationPermissionIfNeeded;

  static const String _channelName = 'app_voz/voice_foreground_service';
  static const String notificationTitle = 'Assistente Hands-Free Ativo';
  static const String notificationMessage = 'Ouvindo comandos musicais...';
  static const String _correlationId = 'foreground_service';

  final VoiceRealtimeEventBus eventBus;
  final MethodChannel _channel;
  final Future<bool> Function() _notificationPermissionRequester;

  var _started = false;
  var _startInFlight = false;

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

      await _channel.invokeMethod<Object?>('startService', {
        'notificationTitle': notificationTitle,
        'notificationText': notificationMessage,
        'notificationPriority': 'low',
        'notificationOngoing': true,
        'notificationIcon': 'ic_launcher',
        'foregroundServiceType': 'microphone',
        'requestedTitle': title,
        'requestedMessage': message,
      });
      _started = true;
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
          },
        ),
      );
    } catch (error) {
      _publishFailure('android_foreground_service_start_failed', error);
      rethrow;
    } finally {
      _startInFlight = false;
    }
  }

  @override
  Future<void> updateMessage(String message) async {
    if (!_started) {
      return;
    }

    try {
      await _channel.invokeMethod<Object?>('updateService', {
        'notificationTitle': notificationTitle,
        'notificationText': message.trim().isEmpty
            ? notificationMessage
            : message,
        'notificationPriority': 'low',
        'notificationOngoing': true,
      });
      eventBus.publish(
        VoiceStateChangedEvent(
          source: 'android_voice_foreground_service',
          previousState: 'foregroundStarted',
          nextState: 'foregroundStarted',
          reason: 'android_foreground_service_updated',
          correlationId: _correlationId,
          metadata: {'message': message},
        ),
      );
    } catch (error) {
      _publishFailure('android_foreground_service_update_failed', error);
      rethrow;
    }
  }

  @override
  Future<void> stopService() async {
    if (!_started && !_startInFlight) {
      return;
    }

    try {
      await _channel.invokeMethod<Object?>('stopService');
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
      rethrow;
    } finally {
      _started = false;
      _startInFlight = false;
    }
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
