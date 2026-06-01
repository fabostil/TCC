import 'package:app_voz/features/voices/realtime/infrastructure/service/android_voice_foreground_service.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_event_bus.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_events.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AndroidVoiceForegroundService', () {
    late _FakeForegroundTaskClient client;
    late VoiceRealtimeEventBus bus;

    setUp(() {
      client = _FakeForegroundTaskClient();
      bus = VoiceRealtimeEventBus();
    });

    test(
      'start inicializa o plugin uma vez e publica notificacao persistente',
      () async {
        final service = AndroidVoiceForegroundService(
          eventBus: bus,
          foregroundTaskClient: client,
          notificationPermissionRequester: () async => true,
        );

        await service.startService(title: 'ignorado', message: 'ignorado');
        await service.startService(title: 'ignorado', message: 'ignorado');

        expect(client.initCalls, 1);
        expect(client.startCalls, hasLength(1));
        expect(
          client.androidNotificationOptions?.channelId,
          'voice_assistant_channel',
        );
        expect(
          client.androidNotificationOptions?.channelName,
          'Assistente Musical',
        );
        expect(
          client.androidNotificationOptions?.channelImportance,
          NotificationChannelImportance.LOW,
        );
        expect(client.iosNotificationOptions?.showNotification, isTrue);
        expect(client.foregroundTaskOptions?.allowWakeLock, isTrue);
        expect(
          client.startCalls.single.notificationTitle,
          'Assistente Musical',
        );
        expect(
          client.startCalls.single.notificationText,
          'Escuta hands-free ligada — Pronto para comandos',
        );
        expect(client.startCalls.single.serviceTypes, [
          ForegroundServiceTypes.microphone,
        ]);
        expect(service.isStarted, isTrue);
        expect(service.isInitialized, isTrue);
      },
    );

    test('stop e idempotente e encerra o plugin uma vez', () async {
      final service = AndroidVoiceForegroundService(
        eventBus: bus,
        foregroundTaskClient: client,
        notificationPermissionRequester: () async => true,
      );

      await service.stopService();
      await service.startService(title: 'titulo', message: 'mensagem');
      await service.stopService();
      await service.stopService();

      expect(client.startCalls, hasLength(1));
      expect(client.stopCalls, 1);
      expect(service.isStarted, isFalse);
    });

    test('falha do plugin publica degradacao sem propagar excecao', () async {
      client.startResult = const ServiceRequestFailure(
        error: MissingForegroundTaskPlugin(),
      );
      final service = AndroidVoiceForegroundService(
        eventBus: bus,
        foregroundTaskClient: client,
        notificationPermissionRequester: () async => true,
      );

      await service.startService(title: 'titulo', message: 'mensagem');

      final degraded = bus.timeline
          .whereType<VoiceSystemDegradedEvent>()
          .single;
      expect(degraded.source, 'android_voice_foreground_service');
      expect(degraded.reason, 'android_foreground_service_start_failed');
      expect(degraded.metadata['error'], contains('foreground task missing'));
      expect(service.isStarted, isFalse);
    });

    test(
      'permissao de notificacao negada degrada mas ainda tenta iniciar servico',
      () async {
        final service = AndroidVoiceForegroundService(
          eventBus: bus,
          foregroundTaskClient: client,
          notificationPermissionRequester: () async => false,
        );

        await service.startService(title: 'titulo', message: 'mensagem');

        expect(client.startCalls, hasLength(1));
        expect(
          bus.timeline.whereType<VoiceSystemDegradedEvent>().single.reason,
          'android_notification_permission_denied',
        );
        expect(service.isStarted, isTrue);
      },
    );
  });
}

class _FakeForegroundTaskClient implements ForegroundTaskClient {
  var initCalls = 0;
  var stopCalls = 0;
  ServiceRequestResult startResult = const ServiceRequestSuccess();
  ServiceRequestResult updateResult = const ServiceRequestSuccess();
  ServiceRequestResult stopResult = const ServiceRequestSuccess();
  AndroidNotificationOptions? androidNotificationOptions;
  IOSNotificationOptions? iosNotificationOptions;
  ForegroundTaskOptions? foregroundTaskOptions;
  final List<_StartCall> startCalls = [];
  final List<_UpdateCall> updateCalls = [];

  @override
  void init({
    required AndroidNotificationOptions androidNotificationOptions,
    required IOSNotificationOptions iosNotificationOptions,
    required ForegroundTaskOptions foregroundTaskOptions,
  }) {
    initCalls += 1;
    this.androidNotificationOptions = androidNotificationOptions;
    this.iosNotificationOptions = iosNotificationOptions;
    this.foregroundTaskOptions = foregroundTaskOptions;
  }

  @override
  Future<ServiceRequestResult> startService({
    required String notificationTitle,
    required String notificationText,
    List<ForegroundServiceTypes>? serviceTypes,
  }) async {
    startCalls.add(
      _StartCall(
        notificationTitle: notificationTitle,
        notificationText: notificationText,
        serviceTypes: serviceTypes,
      ),
    );
    return startResult;
  }

  @override
  Future<ServiceRequestResult> updateService({
    required String notificationTitle,
    required String notificationText,
  }) async {
    updateCalls.add(
      _UpdateCall(
        notificationTitle: notificationTitle,
        notificationText: notificationText,
      ),
    );
    return updateResult;
  }

  @override
  Future<ServiceRequestResult> stopService() async {
    stopCalls += 1;
    return stopResult;
  }
}

class _StartCall {
  const _StartCall({
    required this.notificationTitle,
    required this.notificationText,
    required this.serviceTypes,
  });

  final String notificationTitle;
  final String notificationText;
  final List<ForegroundServiceTypes>? serviceTypes;
}

class _UpdateCall {
  const _UpdateCall({
    required this.notificationTitle,
    required this.notificationText,
  });

  final String notificationTitle;
  final String notificationText;
}

class MissingForegroundTaskPlugin {
  const MissingForegroundTaskPlugin();

  @override
  String toString() => 'foreground task missing';
}
