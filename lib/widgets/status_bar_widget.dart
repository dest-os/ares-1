import 'dart:async';
import 'package:flutter/material.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:battery_plus/battery_plus.dart';

class StatusBarWidget extends StatefulWidget {
  const StatusBarWidget({super.key});

  @override
  State<StatusBarWidget> createState() => _StatusBarWidgetState();
}

class _StatusBarWidgetState extends State<StatusBarWidget> {
  final Battery _battery = Battery();
  int _batteryPercent = 100;
  StreamSubscription<BatteryState>? _batteryStateSub;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _readBattery();
    // Şarja takıldığında / çekildiğinde anında güncelle
    _batteryStateSub = _battery.onBatteryStateChanged.listen((_) => _readBattery());
    // Şarj durumu değişmese bile yüzde zamanla düştüğü için periyodik tazele
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _readBattery());
  }

  Future<void> _readBattery() async {
    try {
      final level = await _battery.batteryLevel;
      if (mounted) {
        setState(() => _batteryPercent = level);
      }
    } catch (e) {
      // Pil bilgisi okunamazsa mevcut değeri koru
    }
  }

  @override
  void dispose() {
    _batteryStateSub?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _openSettings(String action) async {
    try {
      final intent = AndroidIntent(action: action);
      await intent.launch();
    } catch (e) {
      print('Ayar açılamadı: $e');
    }
  }

  // Yatay pil göstergesi: içi, gerçek pil yüzdesine göre dolar/boşalır.
  // Yüzde düştükçe renk de sararır/kırmızıya döner.
  Widget _batteryIcon(int percent) {
    final int p = percent.clamp(0, 100);
    final Color fillColor = p <= 20
        ? Colors.redAccent
        : p <= 40
            ? Colors.amberAccent
            : Colors.white;

    const double bodyWidth = 36;
    const double bodyHeight = 18;
    const double capWidth = 4;
    const double capHeight = 10;
    const double borderWidth = 1.8;
    const double innerPad = 2;

    return SizedBox(
      width: bodyWidth + capWidth + 3,
      height: bodyHeight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: bodyWidth,
            height: bodyHeight,
            padding: const EdgeInsets.all(innerPad),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: borderWidth),
              borderRadius: BorderRadius.circular(6),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: constraints.maxWidth * (p / 100),
                    height: constraints.maxHeight,
                    decoration: BoxDecoration(
                      color: fillColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 3),
          Container(
            width: capWidth,
            height: capHeight,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () => _openSettings('android.settings.WIFI_SETTINGS'),
            child: const Icon(Icons.wifi, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          GestureDetector(
            onTap: () => _openSettings('android.settings.BLUETOOTH_SETTINGS'),
            child: const Icon(Icons.bluetooth, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          GestureDetector(
            onTap: () => _openSettings('android.settings.WIRELESS_SETTINGS'),
            child: const Icon(Icons.signal_cellular_alt, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          GestureDetector(
            onTap: () => _openSettings('android.settings.BATTERY_SAVER_SETTINGS'),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _batteryIcon(_batteryPercent),
                const SizedBox(width: 6),
                Text(
                  '$_batteryPercent%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
