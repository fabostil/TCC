import 'package:app_voz/features/voices/realtime/infrastructure/service/android_voice_foreground_service.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_event_bus.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_events.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AndroidVoiceForegroundService', () {
    const channelName = 'test_android_voice_foreground_service';
    late MethodChannel channel;
    late VoiceRealtimeEventBus bus;

    setUp(() {
      channel = const MethodChannel(channelName);
      bus = VoiceRealtimeEventBus();
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test(
      'start configura notificacao persistente de audio uma unica vez',
      () async {
        final calls = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call);
              return null;
            });
        final service = AndroidVoiceForegroundService(
          eventBus: bus,
          channel: channel,
        );

        await service.startService(title: 'ignorado', message: 'ignorado');
        await service.startService(title: 'ignorado', message: 'ignorado');

        expect(calls, hasLength(1));
        expect(calls.single.method, 'startService');
        expect(calls.single.arguments, {
          'notificationTitle': 'Assistente Hands-Free Ativo',
          'notificationText': 'Ouvindo comandos musicais...',
          'notificationPriority': 'low',
          'notificationOngoing': true,
          'notificationIcon': 'ic_launcher',
          'foregroundServiceType': 'microphone',
          'requestedTitle': 'ignorado',
          'requestedMessage': 'ignorado',
        });
        expect(service.isStarted, isTrue);
      },
    );

    test('stop e idempotente e remove servico nativo uma vez', () async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            return null;
          });
      final service = AndroidVoiceForegroundService(
        eventBus: bus,
        channel: channel,
      );

      await service.stopService();
      await service.startService(title: 'titulo', message: 'mensagem');
      await service.stopService();
      await service.stopService();

      expect(calls, ['startService', 'stopService']);
      expect(service.isStarted, isFalse);
    });

    test(
      'falha nativa publica degradacao e propaga para o ecossistema',
      () async {
        final service = AndroidVoiceForegroundService(
          eventBus: bus,
          channel: channel,
        );

        await expectLater(
          service.startService(title: 'titulo', message: 'mensagem'),
          throwsA(isA<MissingPluginException>()),
        );

        final degraded = bus.timeline
            .whereType<VoiceSystemDegradedEvent>()
            .single;
        expect(degraded.source, 'android_voice_foreground_service');
        expect(degraded.reason, 'android_foreground_service_start_failed');
        expect(service.isStarted, isFalse);
      },
    );
  });
}
