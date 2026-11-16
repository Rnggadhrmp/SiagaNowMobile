import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class EmergencyContactEntry {
  const EmergencyContactEntry({
    required this.id,
    required this.name,
    required this.section,
    required this.phone,
    this.officialSource,
  });

  final String id;
  final String name;
  final String section;
  final String phone;
  final String? officialSource;

  bool get canCall => phone.trim().isNotEmpty;
}

class EmergencyContactsStore {
  EmergencyContactsStore({this._preferences});

  static const storageKey = 'siaganow.emergency_contacts.v1';
  static const entries = <({String id, String name, String section})>[
    (
      id: 'pcc112',
      name: 'Pusat Panggilan Darurat 112 · Kota Padang',
      section: 'Kontak Instansi',
    ),
    (id: 'bpbd', name: 'BPBD', section: 'Kontak Instansi'),
    (id: 'basarnas', name: 'Basarnas', section: 'Kontak Instansi'),
    (id: 'police', name: 'Polisi', section: 'Kontak Instansi'),
    (id: 'fire', name: 'Pemadam Kebakaran', section: 'Kontak Instansi'),
    (id: 'hospital', name: 'Rumah Sakit Terdekat', section: 'Kontak Instansi'),
    (
      id: 'family',
      name: 'Orang Tua / Kerabat',
      section: 'Kontak Orang Terdekat',
    ),
  ];

  SharedPreferences? _preferences;

  Future<SharedPreferences> get _prefs async =>
      _preferences ??= await SharedPreferences.getInstance();

  Future<List<EmergencyContactEntry>> load() async {
    final prefs = await _prefs;
    final raw = prefs.getString(storageKey);
    final values = raw == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(raw) as Map);
    return entries
        .map(
          (entry) => EmergencyContactEntry(
            id: entry.id,
            name: entry.name,
            section: entry.section,
            phone:
                values[entry.id]?.toString() ??
                (entry.id == 'pcc112' ? '112' : ''),
            officialSource: entry.id == 'pcc112'
                ? 'Pusat Pengendalian Operasi 112 Kota Padang (sigap.padang.go.id)'
                : null,
          ),
        )
        .toList(growable: false);
  }

  Future<void> savePhone(String id, String phone) async {
    if (!entries.any((entry) => entry.id == id)) {
      throw ArgumentError.value(id, 'id', 'Kontak tidak dikenal.');
    }
    final prefs = await _prefs;
    final raw = prefs.getString(storageKey);
    final values = raw == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(raw) as Map);
    final normalized = phone.trim();
    if (normalized.isEmpty) {
      values.remove(id);
    } else {
      values[id] = normalized;
    }
    await prefs.setString(storageKey, jsonEncode(values));
  }
}
