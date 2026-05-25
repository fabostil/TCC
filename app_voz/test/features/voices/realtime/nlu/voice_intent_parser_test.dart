import 'package:app_voz/features/voices/realtime/nlu/voice_intent.dart';
import 'package:app_voz/features/voices/realtime/nlu/voice_intent_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VoiceIntentParser', () {
    const parser = VoiceIntentParser();

    test('metronomo com ou sem acento cai na mesma intencao', () {
      final accented = parser.parse('Ligar metrônomo em 120 bpm');
      final plain = parser.parse('ligar metronomo em 120 bpm');

      expect(accented, isA<MetronomeIntent>());
      expect(plain, isA<MetronomeIntent>());
      expect((accented as MetronomeIntent).bpm, 120);
      expect((plain as MetronomeIntent).bpm, accented.bpm);
    });

    test('metronomo aceita sinonimos numericos escopados ao BPM', () {
      final intent = parser.parse('coloca o metrônomo em cento e vinte bpm');

      expect(intent, isA<MetronomeIntent>());
      expect((intent as MetronomeIntent).bpm, 120);
    });

    test('metronomo rejeita BPM malformado ou fora do escopo', () {
      expect(parser.parse('metronomo em 12 bpm'), isA<UnknownIntent>());
      expect(parser.parse('metronomo em 999 bpm'), isA<UnknownIntent>());
    });

    test('girias de playback extraem a acao correta', () {
      final start = parser.parse('solta o som');
      final stop = parser.parse('para a música agora');
      final pause = parser.parse('pausar a musica');

      expect(start, isA<PlaybackIntent>());
      expect((start as PlaybackIntent).action, 'start');
      expect(stop, isA<PlaybackIntent>());
      expect((stop as PlaybackIntent).action, 'stop');
      expect(pause, isA<PlaybackIntent>());
      expect((pause as PlaybackIntent).action, 'pause');
    });

    test('track intents reconhecem acoes locais', () {
      final record = parser.parse('gravar faixa');
      final mute = parser.parse('mutar canal');
      final delete = parser.parse('apagar track');

      expect(record, isA<TrackIntent>());
      expect((record as TrackIntent).action, 'record');
      expect(mute, isA<TrackIntent>());
      expect((mute as TrackIntent).action, 'mute');
      expect(delete, isA<TrackIntent>());
      expect((delete as TrackIntent).action, 'delete');
    });

    test(
      'recording management reconhece delete e rename da ultima gravacao',
      () {
        final delete = parser.parse('apagar última gravação');
        final rename = parser.parse('renomear ultima faixa para voz guia');

        expect(delete, isA<DeleteLastRecordingIntent>());
        expect(rename, isA<RenameLastRecordingIntent>());
        expect((rename as RenameLastRecordingIntent).newName, 'voz guia');
      },
    );

    test('confirmation intents reconhecem confirmar e cancelar isolados', () {
      expect(parser.parse('confirmar'), isA<ConfirmIntent>());
      expect(parser.parse('pode apagar'), isA<ConfirmIntent>());
      expect(parser.parse('cancelar'), isA<CancelIntent>());
      expect(parser.parse('n\u00e3o'), isA<CancelIntent>());
    });

    test('strings aleatorias caem em UnknownIntent sem excecao', () {
      final intent = parser.parse('banana orbital sem contexto 123');

      expect(intent, isA<UnknownIntent>());
      expect(intent.rawText, 'banana orbital sem contexto 123');
    });
  });
}
