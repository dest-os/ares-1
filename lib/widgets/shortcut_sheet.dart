import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import '../models/shortcut.dart';
import '../services/shortcut_service.dart';
import 'neon_container.dart';

class ShortcutSheet extends StatefulWidget {
  final String category;
  /// Sadece ARES kategorisinde gösterilir: Ayarlar ekranını açar.
  final VoidCallback? onSettingsTap;
  /// Yazılı komut gönderildiğinde (ARES).
  final Future<void> Function(String metin)? onTextCommand;

  const ShortcutSheet({
    super.key,
    required this.category,
    this.onSettingsTap,
    this.onTextCommand,
  });

  @override
  State<ShortcutSheet> createState() => _ShortcutSheetState();
}

class _ShortcutSheetState extends State<ShortcutSheet> {
  List<ShortcutItem> _shortcuts = [];
  bool _loading = true;
  // packageName -> icon bytes cache
  final Map<String, Uint8List?> _iconCache = {};
  final TextEditingController _komutCtrl = TextEditingController();
  bool _komutGonderiliyor = false;

  @override
  void dispose() {
    _komutCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ShortcutService().getShortcuts(widget.category);
    if (mounted) {
      setState(() {
        _shortcuts = list;
        _loading = false;
      });
      // İkonları arka planda yükle
      _loadIcons(list);
    }
  }

  Future<void> _loadIcons(List<ShortcutItem> list) async {
    for (final item in list) {
      if (item.packageName == null) continue;
      if (_iconCache.containsKey(item.packageName)) continue;
      try {
        final apps = await InstalledApps.getInstalledApps(false, true);
        for (final app in apps) {
          if (app.packageName == item.packageName && app.icon != null) {
            _iconCache[item.packageName!] = app.icon;
            break;
          }
        }
        if (!_iconCache.containsKey(item.packageName)) {
          _iconCache[item.packageName!] = null;
        }
        if (mounted) setState(() {});
      } catch (_) {}
    }
  }

  Future<void> _remove(String id) async {
    await ShortcutService().removeShortcut(id);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kısayol kaldırıldı (uygulama silinmedi)'),
          backgroundColor: Colors.black87,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _launchApp(ShortcutItem item) async {
    if (item.packageName == null) return;
    try {
      await InstalledApps.startApp(item.packageName!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${item.name} açılamadı'),
            backgroundColor: Colors.red.shade800,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showAddDialog() async {
    List<AppInfo> apps = [];
    try {
      // excludeSystemApps = false → daha fazla uygulama görünür
      // withIcon = true → gerçek ikonlar gelir
      apps = await InstalledApps.getInstalledApps(
        true,  // sadece kullanicinin yukledigi APKlar (sistem haric)
        true,  // ikonlarla birlikte
      );
      apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } catch (e) {
      print('Uygulama listesi alınamadı: $e');
    }

    final existingIds = _shortcuts.map((s) => s.id).toSet();
    final available = apps.where((app) => !existingIds.contains(app.packageName)).toList();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return _AppPickerSheet(
          category: widget.category,
          apps: available,
          onAppSelected: (app) async {
            final item = ShortcutItem(
              id: app.packageName,
              name: app.name,
              icon: '📱', // yedek, gerçek ikon ayrıca yüklenir
              category: widget.category,
              packageName: app.packageName,
            );
            await ShortcutService().addShortcut(item);
            // İkonu cache'e koy
            if (app.icon != null) {
              _iconCache[app.packageName] = app.icon;
            }
            Navigator.pop(ctx);
            await _load();
          },
        );
      },
    );
  }

  Future<void> _yaziliKomutGonder() async {
    final metin = _komutCtrl.text.trim();
    if (metin.isEmpty || widget.onTextCommand == null) return;
    setState(() => _komutGonderiliyor = true);
    try {
      Navigator.pop(context);
      await widget.onTextCommand!(metin);
    } finally {
      if (mounted) setState(() => _komutGonderiliyor = false);
    }
  }

    Widget _buildIcon(ShortcutItem item) {
    final iconBytes = item.packageName != null ? _iconCache[item.packageName] : null;
    if (iconBytes != null) {
      return Image.memory(
        iconBytes,
        width: 40,
        height: 40,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Text(item.icon, style: const TextStyle(fontSize: 28)),
      );
    }
    return Text(item.icon, style: const TextStyle(fontSize: 28));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E17),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF00BFFF).withOpacity(0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00BFFF).withOpacity(0.3),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                widget.category,
                style: const TextStyle(
                  color: Color(0xFF00BFFF),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _showAddDialog,
                icon: const Icon(Icons.add_circle, color: Color(0xFF00BFFF), size: 28),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white54),
              ),
            ],
          ),
          const Divider(color: Color(0xFF00BFFF), height: 20),
          // ARES kategorisinde ayarlar kısayolu (ana tasarımı bozmaz)
          if (widget.category == 'ARES' && widget.onSettingsTap != null) ...[
            NeonContainer(
              onTap: () {
                Navigator.pop(context);
                widget.onSettingsTap!();
              },
              borderRadius: 12,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              margin: const EdgeInsets.only(bottom: 12),
              child: const Row(
                children: [
                  Icon(Icons.settings, color: Color(0xFF00BFFF), size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ARES Ayarları',
                          style: TextStyle(
                            color: Color(0xFF00BFFF),
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'API anahtarları, beyin seçimi, alkış hassasiyeti',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Color(0xFF00BFFF), size: 22),
                ],
              ),
            ),
            // Yazılı komut kutusu
            if (widget.onTextCommand != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _komutCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _yaziliKomutGonder(),
                      decoration: InputDecoration(
                        hintText: "Komut yaz... (ornek: sosyal ac)",
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
                        filled: true,
                        fillColor: Colors.black.withOpacity(0.45),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: const Color(0xFF00BFFF).withOpacity(0.4)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: const Color(0xFF00BFFF).withOpacity(0.35)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: Color(0xFF00BFFF), width: 1.4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _komutGonderiliyor ? null : _yaziliKomutGonder,
                    icon: _komutGonderiliyor
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Color(0xFF00BFFF)),
                          )
                        : const Icon(Icons.send, color: Color(0xFF00BFFF)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
          ],
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(30),
              child: CircularProgressIndicator(color: Color(0xFF00BFFF)),
            )
          else if (_shortcuts.isEmpty)
            Padding(
              padding: const EdgeInsets.all(30),
              child: Column(
                children: [
                  Icon(Icons.apps, color: Colors.white.withOpacity(0.3), size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'Henüz kısayol yok\n+ butonuna basarak ekle',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withOpacity(0.5)),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.85,
                ),
                itemCount: _shortcuts.length,
                itemBuilder: (_, i) {
                  final item = _shortcuts[i];
                  return NeonContainer(
                    onTap: () => _launchApp(item),
                    onLongPress: () => _remove(item.id),
                    borderRadius: 12,
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildIcon(item),
                        const SizedBox(height: 6),
                        Text(
                          item.name,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'Uzun bas = Kısayolu kaldır',
            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _AppPickerSheet extends StatefulWidget {
  final String category;
  final List<AppInfo> apps;
  final Function(AppInfo) onAppSelected;

  const _AppPickerSheet({
    required this.category,
    required this.apps,
    required this.onAppSelected,
  });

  @override
  State<_AppPickerSheet> createState() => _AppPickerSheetState();
}

class _AppPickerSheetState extends State<_AppPickerSheet> {
  late List<AppInfo> _filtered;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filtered = widget.apps;
  }

  void _filter(String query) {
    setState(() {
      if (query.isEmpty) {
        _filtered = widget.apps;
      } else {
        _filtered = widget.apps
            .where((app) => app.name.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E17),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF00BFFF).withOpacity(0.6), width: 1.5),
      ),
      child: Column(
        children: [
          Text(
            '${widget.category} - Uygulama Ekle',
            style: const TextStyle(
              color: Color(0xFF00BFFF),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: _filter,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Uygulama ara...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
              prefixIcon: const Icon(Icons.search, color: Color(0xFF00BFFF)),
              filled: true,
              fillColor: Colors.black.withOpacity(0.4),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: const Color(0xFF00BFFF).withOpacity(0.5)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: const Color(0xFF00BFFF).withOpacity(0.5)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _filtered.isEmpty
                ? Center(
                    child: Text(
                      'Uygulama bulunamadı',
                      style: TextStyle(color: Colors.white.withOpacity(0.5)),
                    ),
                  )
                : ListView.builder(
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) {
                      final app = _filtered[i];
                      return ListTile(
                        leading: app.icon != null
                            ? Image.memory(app.icon!, width: 40, height: 40)
                            : const Icon(Icons.android, color: Color(0xFF00BFFF)),
                        title: Text(app.name, style: const TextStyle(color: Colors.white)),
                        subtitle: Text(
                          app.packageName,
                          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
                        ),
                        trailing: const Icon(Icons.add_circle_outline, color: Color(0xFF00BFFF)),
                        onTap: () => widget.onAppSelected(app),
                      );
                    },
                  ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }
}
