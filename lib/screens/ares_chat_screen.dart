import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/settings_service.dart';
import '../services/llm_service.dart';
import '../services/ares_service.dart';
import 'settings_screen.dart';

class _Msg {
  final String rol;
  final String metin;
  _Msg({required this.rol, required this.metin});
  Map<String, dynamic> toJson() => {'rol': rol, 'metin': metin};
  factory _Msg.fromJson(Map<String, dynamic> j) =>
      _Msg(rol: '${j['rol'] ?? 'sen'}', metin: '${j['metin'] ?? ''}');
}

class _Konu {
  String id;
  String baslik;
  List<_Msg> mesajlar;
  _Konu({required this.id, required this.baslik, List<_Msg>? mesajlar})
      : mesajlar = mesajlar ?? [];
  Map<String, dynamic> toJson() => {
        'id': id,
        'baslik': baslik,
        'mesajlar': mesajlar.map((m) => m.toJson()).toList(),
      };
  factory _Konu.fromJson(Map<String, dynamic> j) => _Konu(
        id: '${j['id']}',
        baslik: '${j['baslik'] ?? 'Sohbet'}',
        mesajlar: ((j['mesajlar'] as List?) ?? [])
            .map((e) => _Msg.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

class AresChatScreen extends StatefulWidget {
  final SettingsService settings;
  final AresService? ares;
  const AresChatScreen({super.key, required this.settings, this.ares});

  @override
  State<AresChatScreen> createState() => _AresChatScreenState();
}

class _AresChatScreenState extends State<AresChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  final _tts = FlutterTts();
  late final LlmService _llm;

  List<_Konu> _konular = [];
  String? _aktifId;
  final List<String> _ekler = [];
  bool _busy = false;
  bool _mic = false;
  bool _sesli = true;

  _Konu get _aktif {
    if (_konular.isEmpty) {
      final k =
          _Konu(id: '${DateTime.now().millisecondsSinceEpoch}', baslik: 'Yeni');
      _konular.add(k);
      _aktifId = k.id;
    }
    return _konular.firstWhere((k) => k.id == _aktifId,
        orElse: () => _konular.first);
  }

  @override
  void initState() {
    super.initState();
    _llm = LlmService(widget.settings);
    _tts.setLanguage('tr-TR');
    _tts.setSpeechRate(0.5);
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    _focus.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('ares_chat_konular');
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List;
      setState(() {
        _konular = list
            .map((e) => _Konu.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        if (_konular.isNotEmpty) _aktifId = _konular.first.id;
      });
    } catch (_) {}
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('ares_chat_konular',
        jsonEncode(_konular.map((k) => k.toJson()).toList()));
  }

  Future<void> _pick() async {
    try {
      final r = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (r == null || r.files.isEmpty) return;
      setState(() {
        for (final f in r.files) {
          _ekler.add(f.name);
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Dosya: $e')));
      }
    }
  }

  Future<void> _micTap() async {
    if (widget.ares == null || !widget.settings.geminiHazir) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Mikrofon icin Gemini anahtari gerekli')));
      }
      return;
    }
    setState(() => _mic = true);
    try {
      await widget.ares!.uyandirVeDinle();
      final m = widget.ares!.sonSoylenen;
      if (m.isNotEmpty) setState(() => _ctrl.text = m);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _mic = false);
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty && _ekler.isEmpty) return;
    if (_busy) return;
    final full = _ekler.isEmpty ? text : '$text\n[Ek: ${_ekler.join(", ")}]';
    setState(() {
      _busy = true;
      _aktif.mesajlar.add(_Msg(rol: 'sen', metin: full));
      if (_aktif.baslik == 'Yeni' && text.isNotEmpty) {
        _aktif.baslik = text.length > 28 ? '${text.substring(0, 28)}...' : text;
      }
      _ctrl.clear();
      _ekler.clear();
    });
    _focus.unfocus();
    await _save();
    _toEnd();

    try {
      await widget.settings.yukle();
      final yanit = await _llm.akilliYanit(full);
      if (!mounted) return;
      setState(() => _aktif.mesajlar.add(_Msg(rol: 'ares', metin: yanit)));
      await _save();
      _toEnd();
      if (_sesli && yanit.isNotEmpty) await _tts.speak(yanit);
    } catch (e) {
      if (!mounted) return;
      setState(() => _aktif.mesajlar.add(_Msg(rol: 'ares', metin: 'Hata: $e')));
      await _save();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent + 40);
      }
    });
  }

  void _geri() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _settingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xE00A1520),
      builder: (ctx) {
        final s = widget.settings;
        final ops = [
          if (s.geminiHazir) ApiProvider.gemini,
          if (s.nvidiaHazir) ApiProvider.nvidia,
          if (s.openaiHazir) ApiProvider.openai,
          if (s.grokHazir) ApiProvider.grok,
          if (s.claudeHazir) ApiProvider.claude,
          if (s.customHazir) ApiProvider.custom,
        ];
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text('Beyin sec',
                    style: TextStyle(
                        color: Color(0xFF00BFFF),
                        fontWeight: FontWeight.bold)),
              ),
              ...ops.map((id) => ListTile(
                    leading: Icon(
                      s.birincilApi == id
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                      color: const Color(0xFF00BFFF),
                    ),
                    title: Text(ApiProvider.etiket(id),
                        style: const TextStyle(color: Colors.white)),
                    onTap: () async {
                      s.birincilApi = id;
                      await s.kaydet();
                      if (ctx.mounted) Navigator.pop(ctx);
                      setState(() {});
                    },
                  )),
              ListTile(
                leading: const Icon(Icons.settings, color: Color(0xFF00BFFF)),
                title: const Text('Tum ayarlar',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          SettingsScreen(settings: widget.settings),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final w = size.width;
    final h = size.height;
    final pad = MediaQuery.of(context).viewInsets.bottom;
    final topPad = MediaQuery.of(context).padding.top;

    // Gorseldeki alt cubuk yaklasik oranlari (landscape)
    final bottomBarH = h * 0.11;
    final inputBottom = 8.0 + pad;

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/ares_chat_bg.png',
            fit: BoxFit.cover,
            width: w,
            height: h,
            errorBuilder: (_, __, ___) =>
                Container(color: const Color(0xFF02050A)),
          ),

          // ----- UST BAR: gercek butonlar (kayma yok, pop karismasi yok) -----
          Positioned(
            left: 0,
            right: 0,
            top: topPad,
            height: 52,
            child: Row(
              children: [
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Geri',
                  onPressed: _geri,
                  icon: const Icon(Icons.arrow_back_ios_new, size: 22),
                  color: const Color(0xFF00BFFF),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Sesli yanit',
                  onPressed: () => setState(() => _sesli = !_sesli),
                  icon: Icon(_sesli ? Icons.volume_up : Icons.volume_off),
                  color: const Color(0xFF00BFFF),
                ),
                IconButton(
                  tooltip: 'Ayarlar / beyin',
                  onPressed: _settingsSheet,
                  icon: const Icon(Icons.settings),
                  color: const Color(0xFF00BFFF),
                ),
                IconButton(
                  tooltip: 'Kapat',
                  onPressed: _geri,
                  icon: const Icon(Icons.close),
                  color: Colors.white70,
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),

          // ----- MESAJLAR -----
          Positioned(
            left: w * 0.30,
            right: w * 0.03,
            top: topPad + 56,
            bottom: bottomBarH + pad + 4,
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              itemCount: _aktif.mesajlar.length + (_busy ? 1 : 0),
              itemBuilder: (_, i) {
                if (_busy && i == _aktif.mesajlar.length) {
                  return const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFF00BFFF)),
                      ),
                    ),
                  );
                }
                final m = _aktif.mesajlar[i];
                final me = m.rol == 'sen';
                return Align(
                  alignment:
                      me ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    constraints: BoxConstraints(maxWidth: w * 0.42),
                    decoration: BoxDecoration(
                      color: me
                          ? const Color(0xFF00BFFF).withOpacity(0.32)
                          : Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFF00BFFF).withOpacity(0.4)),
                    ),
                    child: Text(
                      m.metin,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14, height: 1.3),
                    ),
                  ),
                );
              },
            ),
          ),

          // ----- ALT KONTROL CUBUGU (gorselin uzerinde, hizali) -----
          Positioned(
            left: w * 0.28,
            right: w * 0.02,
            bottom: inputBottom,
            height: bottomBarH * 0.85,
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_ekler.isNotEmpty)
                    SizedBox(
                      height: 22,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: _ekler
                            .map((e) => Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Chip(
                                    label: Text(e,
                                        style: const TextStyle(fontSize: 10)),
                                    onDeleted: () =>
                                        setState(() => _ekler.remove(e)),
                                    visualDensity: VisualDensity.compact,
                                    backgroundColor: Colors.black54,
                                    labelStyle:
                                        const TextStyle(color: Colors.white),
                                    deleteIconColor: Colors.white54,
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // +
                        IconButton(
                          onPressed: _pick,
                          icon: const Icon(Icons.add, size: 28),
                          color: const Color(0xFF00BFFF),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 44, minHeight: 44),
                        ),
                        // Yazi alani — sinirli, tasmaz
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(22),
                            child: Container(
                              height: 44,
                              alignment: Alignment.centerLeft,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              color: Colors.black.withOpacity(0.40),
                              child: TextField(
                                controller: _ctrl,
                                focusNode: _focus,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 15),
                                cursorColor: const Color(0xFF00BFFF),
                                maxLines: 1,
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) => _send(),
                                decoration: InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                  hintText: 'Mesaj yaz...',
                                  hintStyle: TextStyle(
                                      color: Colors.white.withOpacity(0.35),
                                      fontSize: 14),
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Mikrofon
                        IconButton(
                          onPressed: _mic ? null : _micTap,
                          icon: Icon(_mic ? Icons.mic : Icons.mic_none,
                              size: 26),
                          color: _mic
                              ? Colors.redAccent
                              : const Color(0xFF00BFFF),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 44, minHeight: 44),
                        ),
                        // Gonder
                        IconButton(
                          onPressed: _busy ? null : _send,
                          icon: _busy
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF00BFFF)),
                                )
                              : const Icon(Icons.send, size: 24),
                          color: const Color(0xFF00BFFF),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 44, minHeight: 44),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
