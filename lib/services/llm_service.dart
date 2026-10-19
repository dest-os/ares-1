import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'settings_service.dart';

/// Metin tabanlı LLM çağrıları.
/// Ses tanıma ayrı (AresService + Gemini audio); bu servis yazılı/akıllı yanıt içindir.
class LlmService {
  final SettingsService settings;

  LlmService(this.settings);

  /// Kisa Turkce yanit. Birincil beyin basarisizsa (429/404) diger kayitli API'lere gecer.
  Future<String> akilliYanit(String kullaniciMesaji) async {
    final mesaj = kullaniciMesaji.trim();
    if (mesaj.isEmpty) {
      throw Exception('Bos mesaj');
    }

    final sistem = 'Sen ${settings.asistanAdi} adinda, ${settings.sahipAdi} adli '
        'kullanicinin Turkce konusan kisa ve net bir asistanisin. '
        'Cevaplarin 1-3 cumleyi gecmesin. Kod veya markdown yazma.';

    // Sira: once birincil, sonra hazir olan digerleri
    final siralar = <String>[
      settings.birincilApi,
      ApiProvider.nvidia,
      ApiProvider.openai,
      ApiProvider.grok,
      ApiProvider.custom,
      ApiProvider.claude,
      ApiProvider.gemini,
    ];
    final denenen = <String>[];
    for (final p in siralar) {
      if (denenen.contains(p)) continue;
      denenen.add(p);
    }

    String sonHata = '';
    for (final provider in denenen) {
      try {
        final yanit = await _tekSaglayici(provider, sistem, mesaj);
        if (yanit.trim().isNotEmpty) {
          debugPrint('LlmService basarili provider: $provider');
          return yanit;
        }
      } catch (e) {
        sonHata = e.toString();
        debugPrint('LlmService $provider hata: $e');
        // 401 anahtar yoksa sonraki; 429 kotada sonraki
        continue;
      }
    }
    throw Exception(
      'Tum beyinler yanit veremedi. Son hata: $sonHata. '
      'Gemini kota veya anahtarlari kontrol et.',
    );
  }

  Future<String> _tekSaglayici(
    String provider,
    String sistem,
    String mesaj,
  ) async {
    switch (provider) {
      case ApiProvider.nvidia:
        if (!settings.nvidiaHazir) throw Exception('NVIDIA anahtar yok');
        return await _openaiUyumluCagir(
          baseUrl: 'https://integrate.api.nvidia.com/v1',
          apiKey: settings.nvidiaApiKey,
          model: settings.nvidiaModel.trim().isEmpty
              ? 'meta/llama-3.1-8b-instruct'
              : settings.nvidiaModel.trim(),
          sistem: sistem,
          kullanici: mesaj,
        );
      case ApiProvider.openai:
        if (!settings.openaiHazir) throw Exception('OpenAI anahtar yok');
        return await _openaiUyumluCagir(
          baseUrl: 'https://api.openai.com/v1',
          apiKey: settings.openaiApiKey,
          model: 'gpt-4o-mini',
          sistem: sistem,
          kullanici: mesaj,
        );
      case ApiProvider.grok:
        if (!settings.grokHazir) throw Exception('Grok anahtar yok');
        return await _openaiUyumluCagir(
          baseUrl: 'https://api.x.ai/v1',
          apiKey: settings.grokApiKey,
          model: 'grok-2-latest',
          sistem: sistem,
          kullanici: mesaj,
        );
      case ApiProvider.custom:
        if (!settings.customHazir) throw Exception('Ozel API yok');
        return await _openaiUyumluCagir(
          baseUrl: _normalizeBase(settings.customApiBaseUrl),
          apiKey: settings.customApiKey,
          model: 'default',
          sistem: sistem,
          kullanici: mesaj,
        );
      case ApiProvider.claude:
        if (!settings.claudeHazir) throw Exception('Claude anahtar yok');
        return await _claudeCagir(sistem: sistem, kullanici: mesaj);
      case ApiProvider.gemini:
      default:
        if (!settings.geminiHazir) throw Exception('Gemini anahtar yok');
        return await _geminiMetin(sistem: sistem, kullanici: mesaj);
    }
  }

  /// Ayarlar ekrani test butonu — her zaman okunabilir Turkce sonuc.
  Future<String> baglantiTesti() async {
    final beyin = settings.birincilEtiket;
    if (!settings.birincilHazir) {
      return 'Secili beyin ($beyin) icin API anahtari eksik. '
          'Once anahtari yapistirip KAYDET, sonra test et.';
    }
    try {
      final yanit = await akilliYanit('Sadece su kelimeleri yaz: baglanti tamam');
      if (yanit.trim().isEmpty) {
        return 'Sunucu bos yanit dondu. Model adini kontrol et ($beyin).';
      }
      return 'Basarili ($beyin): $yanit';
    } catch (e) {
      final msg = e.toString();
      debugPrint('baglantiTesti hata: $msg');
      // Kullaniciya kisaltilmis net mesaj
      if (msg.contains('401') || msg.contains('403')) {
        return 'Yetki hatasi (401/403): API anahtari yanlis veya suresi dolmus. ($beyin)';
      }
      if (msg.contains('404')) {
        return 'Model bulunamadi (404): Model adini kontrol et. ($beyin)';
      }
      if (msg.contains('429')) {
        return 'Kota asildi (429): Biraz bekleyip tekrar dene. ($beyin)';
      }
      if (msg.contains('SocketException') ||
          msg.contains('Failed host lookup') ||
          msg.contains('Network')) {
        return 'Internet baglantisi yok veya engellenmis.';
      }
      final kisa = msg.length > 180 ? '${msg.substring(0, 180)}...' : msg;
      return 'Hata ($beyin): $kisa';
    }
  }

  String _normalizeBase(String url) {
    var u = url.trim();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    if (u.endsWith('/chat/completions')) {
      u = u.replaceAll(RegExp(r'/chat/completions$'), '');
    }
    return u;
  }

  Future<String> _openaiUyumluCagir({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String sistem,
    required String kullanici,
  }) async {
    final base = _normalizeBase(baseUrl);
    final uri = Uri.parse('$base/chat/completions');
    final govde = jsonEncode({
      'model': model,
      'messages': [
        {'role': 'system', 'content': sistem},
        {'role': 'user', 'content': kullanici},
      ],
      'temperature': 0.6,
      'max_tokens': 200,
    });
    final yanit = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${apiKey.trim()}',
          },
          body: govde,
        )
        .timeout(const Duration(seconds: 45));
    if (yanit.statusCode < 200 || yanit.statusCode >= 300) {
      final body = yanit.body.length > 200
          ? yanit.body.substring(0, 200)
          : yanit.body;
      throw Exception('HTTP ${yanit.statusCode}: $body');
    }
    final data = jsonDecode(yanit.body) as Map<String, dynamic>;
    final content = data['choices']?[0]?['message']?['content'];
    final text = content?.toString().trim() ?? '';
    if (text.isEmpty) {
      throw Exception('Bos icerik: ${yanit.body.length > 100 ? yanit.body.substring(0, 100) : yanit.body}');
    }
    return text;
  }

  Future<String> _claudeCagir({
    required String sistem,
    required String kullanici,
  }) async {
    final uri = Uri.parse('https://api.anthropic.com/v1/messages');
    final govde = jsonEncode({
      'model': 'claude-3-5-haiku-latest',
      'max_tokens': 200,
      'system': sistem,
      'messages': [
        {'role': 'user', 'content': kullanici},
      ],
    });
    final yanit = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': settings.claudeApiKey.trim(),
            'anthropic-version': '2023-06-01',
          },
          body: govde,
        )
        .timeout(const Duration(seconds: 45));
    if (yanit.statusCode < 200 || yanit.statusCode >= 300) {
      throw Exception('Claude HTTP ${yanit.statusCode}: ${yanit.body.length > 120 ? yanit.body.substring(0, 120) : yanit.body}');
    }
    final data = jsonDecode(yanit.body) as Map<String, dynamic>;
    final blocks = data['content'] as List? ?? [];
    if (blocks.isEmpty) {
      throw Exception('Claude bos content');
    }
    final text = blocks.first['text']?.toString().trim() ?? '';
    if (text.isEmpty) throw Exception('Claude bos metin');
    return text;
  }

  /// API anahtariyla kullanilabilir modelleri listeler.
  Future<List<String>> _geminiModelleriListele() async {
    try {
      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models'
        '?key=${settings.geminiApiKey.trim()}',
      );
      final yanit = await http.get(uri).timeout(const Duration(seconds: 15));
      if (yanit.statusCode != 200) return [];
      final data = jsonDecode(yanit.body) as Map<String, dynamic>;
      final models = data['models'] as List? ?? [];
      final isimler = <String>[];
      for (final m in models) {
        final name = (m['name'] ?? '').toString(); // models/gemini-x
        final methods = (m['supportedGenerationMethods'] as List? ?? [])
            .map((e) => e.toString())
            .toList();
        if (!methods.contains('generateContent')) continue;
        final id = name.replaceFirst('models/', '');
        if (id.isNotEmpty) isimler.add(id);
      }
      return isimler;
    } catch (e) {
      debugPrint('Gemini model listesi alinamadi: $e');
      return [];
    }
  }

  /// Gemini metin — once listedeki modeller, sonra bilinen guncel isimler.
  Future<String> _geminiMetin({
    required String sistem,
    required String kullanici,
  }) async {
    final tercih = settings.geminiModel.trim();
    // 2026 resmi metin modelleri (ai.google.dev)
    final bilinen = <String>[
      'gemini-3.8-flash',
      'gemini-3.7-flash',
      'gemini-3.6-flash',
      'gemini-3.5-flash',
            'gemini-2.5-flash',
            'gemini-2.5-pro',
    ];
    final apiListesi = await _geminiModelleriListele();
    // Flash / pro oncelikli siralama
    final flashlar = apiListesi
        .where((m) =>
            m.contains('flash') &&
            !m.contains('tts') &&
            !m.contains('image') &&
            !m.contains('live'))
        .toList();
    final modeller = <String>[
      if (tercih.isNotEmpty) tercih,
      ...flashlar,
      ...apiListesi,
      ...bilinen,
    ];
    final sirali = <String>[];
    for (final m in modeller) {
      if (m.isNotEmpty && !sirali.contains(m)) sirali.add(m);
    }
    if (sirali.isEmpty) {
      throw Exception('Kullanilabilir Gemini modeli bulunamadi. Anahtari kontrol et.');
    }

    String sonHata = '';
    for (final model in sirali.take(12)) {
      try {
        return await _geminiTekModel(
          model: model,
          sistem: sistem,
          kullanici: kullanici,
        );
      } catch (e) {
        sonHata = e.toString();
        debugPrint('Gemini model $model basarisiz: $e');
        if (sonHata.contains('401') ||
            sonHata.contains('403') ||
            sonHata.contains('API_KEY_INVALID')) {
          rethrow;
        }
      }
    }
    throw Exception(
        'Hicbir Gemini modeli yanit vermedi. '
        'Denenen: ${sirali.take(8).join(", ")}. Son hata: $sonHata');
  }

  Future<String> _geminiTekModel({
    required String model,
    required String sistem,
    required String kullanici,
  }) async {
    final key = settings.geminiApiKey.trim();
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent',
    );
    final govde = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': '$sistem\n\nKullanici: $kullanici'},
          ],
        },
      ],
    });
    final yanit = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': key,
          },
          body: govde,
        )
        .timeout(const Duration(seconds: 30));
    if (yanit.statusCode != 200) {
      throw Exception(
          'Gemini HTTP ${yanit.statusCode} ($model): '
          '${yanit.body.length > 150 ? yanit.body.substring(0, 150) : yanit.body}');
    }
    final data = jsonDecode(yanit.body) as Map<String, dynamic>;
    if (data['candidates'] == null) {
      final sebep = data['promptFeedback']?['blockReason'] ?? data['error'];
      throw Exception('Gemini aday yok ($model): $sebep');
    }
    final text =
        data['candidates']?[0]?['content']?['parts']?[0]?['text']?.toString().trim() ??
            '';
    if (text.isEmpty) {
      throw Exception('Gemini bos metin ($model)');
    }
    return text;
  }
}
