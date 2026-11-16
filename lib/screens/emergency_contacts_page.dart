import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/emergency_contacts_store.dart';
import '../widgets/siaganow_page_background.dart';

class EmergencyContactsPage extends StatefulWidget {
  const EmergencyContactsPage({
    super.key,
    this.embedded = false,
    this.store,
    this.dialer,
  });

  final bool embedded;
  final EmergencyContactsStore? store;
  final Future<bool> Function(Uri)? dialer;

  @override
  State<EmergencyContactsPage> createState() => _EmergencyContactsPageState();
}

class _EmergencyContactsPageState extends State<EmergencyContactsPage> {
  late final EmergencyContactsStore _store =
      widget.store ?? EmergencyContactsStore();
  List<EmergencyContactEntry> contacts = const [];
  bool loading = true;
  String? loadError;

  @override
  void initState() {
    super.initState();
    loadContacts();
  }

  Future<void> loadContacts() async {
    setState(() {
      loading = true;
      loadError = null;
    });
    try {
      contacts = await _store.load();
    } catch (_) {
      loadError = 'Kontak belum dapat dimuat. Coba muat ulang.';
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _call(EmergencyContactEntry contact) async {
    if (!contact.canCall) return;
    final uri = Uri(scheme: 'tel', path: contact.phone);
    final opened = await (widget.dialer ?? launchUrl)(uri);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dialer tidak tersedia pada perangkat ini.'),
        ),
      );
    }
  }

  Future<void> _editSection(String section) async {
    final sectionContacts = contacts.where(
      (contact) => contact.section == section,
    );
    if (sectionContacts.length == 1) {
      await _editContact(sectionContacts.single);
      return;
    }
    final selected = await showDialog<EmergencyContactEntry>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          section == 'Kontak Instansi'
              ? 'Pilih kontak instansi'
              : 'Pilih kontak',
        ),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: sectionContacts
                .map(
                  (contact) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(contact.name),
                    subtitle: Text(
                      contact.canCall ? contact.phone : 'Belum diisi',
                    ),
                    onTap: () => Navigator.pop(context, contact),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
    if (selected != null) await _editContact(selected);
  }

  Future<void> _editContact(EmergencyContactEntry contact) async {
    final value = await showDialog<String?>(
      context: context,
      builder: (_) => _EmergencyContactEditDialog(contact: contact),
    );
    if (value == null) return;
    try {
      await _store.savePhone(contact.id, value);
      await loadContacts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kontak tersimpan di perangkat ini.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kontak belum dapat disimpan. Coba lagi.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = loading
        ? const Center(child: CircularProgressIndicator())
        : loadError != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(loadError!, textAlign: TextAlign.center),
                TextButton(
                  onPressed: loadContacts,
                  child: const Text('Coba lagi'),
                ),
              ],
            ),
          )
        : ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 112),
            children: [
              const Text(
                'Kontak Instansi',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              ...contacts
                  .where((contact) => contact.section == 'Kontak Instansi')
                  .map(_contactRow),
              _sectionEditButton('Kontak Instansi'),
              const SizedBox(height: 22),
              const Text(
                'Kontak Orang Terdekat',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              ...contacts
                  .where(
                    (contact) => contact.section == 'Kontak Orang Terdekat',
                  )
                  .map(_contactRow),
              _sectionEditButton('Kontak Orang Terdekat'),
              const SizedBox(height: 20),
              Card(
                color: Colors.white,
                child: ListTile(
                  leading: const Icon(
                    Icons.mic_none_outlined,
                    color: Color(0xFF52645D),
                  ),
                  title: const Text('Tinggalkan Pesan Suara'),
                  subtitle: const Text('Belum tersedia'),
                  trailing: const Icon(
                    Icons.lock_outline,
                    color: Color(0xFF697A73),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Nomor yang Anda tambahkan disimpan di perangkat ini. Tekan ikon telepon untuk membuka dialer.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF43554E)),
                ),
              ),
            ],
          );
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: const SiagaNowHeaderBackground(),
        title: const Text('Daftar Kontak'),
      ),
      body: SiagaNowPageBackground(child: content),
    );
  }

  Widget _contactRow(EmergencyContactEntry contact) {
    final isKnown112 = contact.officialSource != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: const Color(0xFF01543F),
        borderRadius: BorderRadius.circular(13),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          minVerticalPadding: 10,
          title: Text(
            contact.name,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            contact.canCall
                ? '${contact.phone}${isKnown112 ? '\nSumber: ${contact.officialSource}' : ''}'
                : 'Belum diisi — ketuk Edit untuk menambahkan',
            style: const TextStyle(color: Color(0xFFE1F2E9), height: 1.35),
            maxLines: isKnown112 ? 3 : 2,
          ),
          isThreeLine: isKnown112,
          trailing: IconButton(
            tooltip: contact.canCall
                ? 'Buka dialer untuk ${contact.name}'
                : 'Nomor belum diisi',
            onPressed: contact.canCall ? () => _call(contact) : null,
            icon: Icon(
              Icons.call_outlined,
              color: contact.canCall
                  ? const Color(0xFFFF7770)
                  : const Color(0xFF9FB6AE),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionEditButton(String section) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: OutlinedButton.icon(
      onPressed: () => _editSection(section),
      icon: const Icon(Icons.edit_outlined),
      label: const Text('Edit / Tambah Kontak'),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF01543F),
        backgroundColor: Colors.white,
        minimumSize: const Size.fromHeight(46),
      ),
    ),
  );
}

class _EmergencyContactEditDialog extends StatefulWidget {
  const _EmergencyContactEditDialog({required this.contact});

  final EmergencyContactEntry contact;

  @override
  State<_EmergencyContactEditDialog> createState() =>
      _EmergencyContactEditDialogState();
}

class _EmergencyContactEditDialogState
    extends State<_EmergencyContactEditDialog> {
  late final controller = TextEditingController(text: widget.contact.phone);
  final formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contact = widget.contact;
    return AlertDialog(
      backgroundColor: Colors.white,
      title: Text(
        contact.phone.isEmpty
            ? 'Tambah ${contact.name}'
            : 'Edit ${contact.name}',
      ),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.phone,
          inputFormatters: [LengthLimitingTextInputFormatter(24)],
          decoration: const InputDecoration(
            labelText: 'Nomor telepon',
            hintText: 'Masukkan nomor yang sudah Anda verifikasi',
            border: OutlineInputBorder(),
          ),
          validator: (value) {
            final number = value?.trim() ?? '';
            if (number.isEmpty) return null;
            if (number.length < 3 ||
                !RegExp(r'^[+0-9 ()-]+$').hasMatch(number)) {
              return 'Periksa format nomor telepon.';
            }
            return null;
          },
        ),
      ),
      actions: [
        if (contact.phone.isNotEmpty)
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('Hapus'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.pop(context, controller.text.trim());
            }
          },
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}
