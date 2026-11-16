import 'dart:async';

import 'package:flutter/material.dart';

import '../models/donation_campaign.dart';
import '../services/donation_repository.dart';
import '../widgets/siaganow_page_background.dart';

class DonationPage extends StatefulWidget {
  const DonationPage({
    super.key,
    required this.repository,
    this.embedded = false,
    this.loggedIn = false,
    this.onLogin,
  });

  final DonationRepository repository;
  final bool embedded;
  final bool loggedIn;
  final Future<void> Function()? onLogin;

  @override
  State<DonationPage> createState() => _DonationPageState();
}

class _DonationPageState extends State<DonationPage> {
  bool loading = true;
  bool raisingFund = false;
  String query = '';
  String? error;
  List<DonationCampaign> campaigns = const [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      campaigns = await widget.repository.loadCampaigns();
    } catch (_) {
      error =
          'Program donasi belum dapat dimuat. Periksa koneksi lalu coba lagi.';
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _donate(DonationCampaign campaign) async {
    if (!widget.loggedIn) {
      await widget.onLogin?.call();
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => DonationAmountPage(campaign: campaign)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = ListView(
      key: const ValueKey('donation-catalog-list'),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 112),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFDFF4E8), Color(0xFFBDE6D0)],
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: const Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Donasi',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text('Program bantuan yang terverifikasi SiagaNow.'),
                  ],
                ),
              ),
              SizedBox(width: 12),
              Icon(
                Icons.volunteer_activism_outlined,
                size: 42,
                color: Color(0xFF075B49),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Row(
            children: [
              _DonationModePill(
                title: 'Donasi',
                selected: !raisingFund,
                onTap: () => setState(() => raisingFund = false),
              ),
              _DonationModePill(
                title: 'Galang Dana',
                selected: raisingFund,
                onTap: () => setState(() => raisingFund = true),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (raisingFund)
          const _DonationMessage(
            icon: Icons.hourglass_empty,
            title: 'Galang Dana segera hadir',
            message: 'Fitur membuat program penggalangan dana belum tersedia.',
          )
        else ...[
          TextField(
            onChanged: (value) =>
                setState(() => query = value.trim().toLowerCase()),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Cari program donasi',
              suffixIcon: IconButton(
                tooltip: 'Cari program',
                onPressed: () => FocusScope.of(context).unfocus(),
                icon: const Icon(Icons.arrow_forward),
              ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (error != null)
            _DonationMessage(
              icon: Icons.cloud_off_outlined,
              title: 'Daftar belum tersedia',
              message: error!,
              action: TextButton(
                onPressed: load,
                child: const Text('Coba lagi'),
              ),
            )
          else if (campaigns.isEmpty)
            const _DonationMessage(
              icon: Icons.volunteer_activism_outlined,
              title: 'Belum ada program donasi terverifikasi',
              message: 'Program akan tampil setelah tersedia dari katalog resmi SiagaNow.',
            )
          else
            ...campaigns
                .where(
                  (campaign) =>
                      query.isEmpty ||
                      '${campaign.title} ${campaign.description} ${campaign.organizer}'
                          .toLowerCase()
                          .contains(query),
                )
                .map((campaign) => _campaignCard(campaign)),
          if (!loading &&
              error == null &&
              campaigns.isNotEmpty &&
              _visibleCampaigns.isEmpty)
            const _DonationMessage(
              icon: Icons.search_off,
              title: 'Program tidak ditemukan',
              message: 'Coba kata kunci lain.',
            ),
        ],
        const SizedBox(height: 10),
        const Text(
          'Pembayaran dalam aplikasi belum tersedia. Tidak ada transaksi atau total donasi yang dicatat.',
          style: TextStyle(fontSize: 12, color: Color(0xFF42564D)),
        ),
      ],
    );
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: const SiagaNowHeaderBackground(),
        title: const Text('Donasi'),
      ),
      body: SiagaNowPageBackground(child: content),
    );
  }

  List<DonationCampaign> get _visibleCampaigns => campaigns
      .where(
        (campaign) =>
            query.isEmpty ||
            '${campaign.title} ${campaign.description} ${campaign.organizer}'
                .toLowerCase()
                .contains(query),
      )
      .toList(growable: false);

  Widget _campaignCard(DonationCampaign campaign) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    color: Colors.white,
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => DonationDetailPage(
            campaign: campaign,
            onDonate: () => _donate(campaign),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 74,
              height: 88,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4F2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.image_outlined,
                    color: Color(0xFF75847D),
                    size: 20,
                  ),
                  SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Foto belum tersedia',
                      style: TextStyle(fontSize: 9),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    campaign.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  if (campaign.isVerified)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'Program terverifikasi',
                        style: TextStyle(
                          color: Color(0xFF087653),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    campaign.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      height: 1.35,
                      color: Color(0xFF52645D),
                    ),
                  ),
                  if (campaign.targetAmount != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Target ${_rupiah(campaign.targetAmount!)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF174B38),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => _openDetails(campaign),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Lihat Informasi'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  void _openDetails(DonationCampaign campaign) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DonationDetailPage(
          campaign: campaign,
          onDonate: () => _donate(campaign),
        ),
      ),
    );
  }
}

class DonationDetailPage extends StatelessWidget {
  const DonationDetailPage({
    super.key,
    required this.campaign,
    required this.onDonate,
  });

  final DonationCampaign campaign;
  final VoidCallback onDonate;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      flexibleSpace: const SiagaNowHeaderBackground(),
      title: const Text('Informasi Donasi'),
    ),
    body: SiagaNowPageBackground(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Container(
            height: 190,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF1ED),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Text(
              'Foto belum tersedia',
              style: TextStyle(color: Color(0xFF52645D)),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            campaign.title,
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
          ),
          if (campaign.isVerified)
            const Padding(
              padding: EdgeInsets.only(top: 7),
              child: Text(
                'Program terverifikasi SiagaNow',
                style: TextStyle(
                  color: Color(0xFF087653),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (campaign.organizer.isNotEmpty) ...[
            const SizedBox(height: 14),
            Card(
              color: Colors.white,
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.apartment)),
                title: Text(campaign.organizer),
                subtitle: Text(
                  campaign.sourceName.isEmpty
                      ? 'Penggalang program'
                      : campaign.sourceName,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          const Text(
            'Informasi Kejadian',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            campaign.description.isEmpty
                ? 'Deskripsi program belum tersedia.'
                : campaign.description,
            style: const TextStyle(height: 1.5),
          ),
          if (campaign.targetAmount != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Colors.white,
              child: ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Target program'),
                subtitle: Text(_rupiah(campaign.targetAmount!)),
              ),
            ),
          ],
          const SizedBox(height: 14),
          const Text(
            'Informasi pengumpulan dana belum tersedia dari katalog. Total dana dan persentase tidak ditampilkan.',
            style: TextStyle(color: Color(0xFF52645D)),
          ),
          if (campaign.sourceUrl != null) ...[
            const SizedBox(height: 8),
            SelectableText(
              'Sumber: ${campaign.sourceName.isEmpty ? campaign.sourceUrl : campaign.sourceName}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: onDonate,
            icon: const Icon(Icons.volunteer_activism_outlined),
            label: const Text('Donasi Sekarang'),
          ),
        ],
      ),
    ),
  );
}

class DonationAmountPage extends StatefulWidget {
  const DonationAmountPage({super.key, required this.campaign});

  final DonationCampaign campaign;

  @override
  State<DonationAmountPage> createState() => _DonationAmountPageState();
}

class _DonationAmountPageState extends State<DonationAmountPage> {
  static const amounts = [
    5000,
    10000,
    20000,
    50000,
    100000,
    150000,
    200000,
    500000,
    1000000,
  ];
  final custom = TextEditingController();
  int? selected;
  String? error;

  @override
  void dispose() {
    custom.dispose();
    super.dispose();
  }

  int? get amount =>
      selected ?? int.tryParse(custom.text.replaceAll(RegExp(r'[^0-9]'), ''));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      flexibleSpace: const SiagaNowHeaderBackground(),
      title: const Text('Pilih Nominal'),
    ),
    body: SiagaNowPageBackground(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            color: Colors.white,
            child: ListTile(
              title: Text(
                widget.campaign.title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                'Penerima: ${widget.campaign.organizer.isEmpty ? 'Informasi belum tersedia' : widget.campaign.organizer}',
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Pilih nominal donasi',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.8,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            children: amounts
                .map(
                  (value) => ChoiceChip(
                    label: Text(
                      _compactRupiah(value),
                      textAlign: TextAlign.center,
                    ),
                    selected: selected == value,
                    onSelected: (_) => setState(() {
                      selected = value;
                      custom.clear();
                      error = null;
                    }),
                    selectedColor: const Color(0xFFD4F0E0),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: custom,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {
              selected = null;
              error = null;
            }),
            decoration: InputDecoration(
              labelText: 'Nominal Donasi Lainnya',
              prefixText: 'Rp ',
              border: const OutlineInputBorder(),
              errorText: error,
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Minimum donasi Rp5.000.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _continue,
            child: const Text('Lanjutkan Pembayaran'),
          ),
        ],
      ),
    ),
  );

  void _continue() {
    final value = amount;
    if (value == null || value < 5000) {
      setState(() => error = 'Nominal minimum Rp5.000.');
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            DonationPaymentPage(campaign: widget.campaign, amount: value),
      ),
    );
  }
}

class DonationPaymentPage extends StatelessWidget {
  const DonationPaymentPage({
    super.key,
    required this.campaign,
    required this.amount,
  });

  final DonationCampaign campaign;
  final int amount;
  static const methods = [
    'QRIS',
    'BCA',
    'BRI',
    'ShopeePay',
    'BNI',
    'Metode Lainnya',
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      flexibleSpace: const SiagaNowHeaderBackground(),
      title: const Text('Metode Pembayaran'),
    ),
    body: SiagaNowPageBackground(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            color: Colors.white,
            child: ListTile(
              title: Text(
                campaign.title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text('Nominal donasi ${_rupiah(amount)}'),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Metode pembayaran',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Belum ada penyedia pembayaran yang dikonfigurasi. Metode belum dapat dipilih.',
          ),
          const SizedBox(height: 12),
          ...methods.map(
            (method) => Card(
              color: const Color(0xFFF0F2F1),
              child: ListTile(
                enabled: false,
                leading: const Icon(Icons.lock_outline),
                title: Text(method),
                trailing: const Text('Belum tersedia'),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => _unavailable(context),
            child: const Text('Lanjutkan Pembayaran'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tidak akan dibuat transaksi, QR, atau nomor virtual account dari aplikasi ini.',
            style: TextStyle(fontSize: 12, color: Color(0xFF52645D)),
          ),
        ],
      ),
    ),
  );

  Future<void> _unavailable(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('Pembayaran belum tersedia'),
      content: const Text(
        'Pembayaran belum tersedia di versi ini. Tidak ada transaksi yang dibuat.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
      ],
    ),
  );
}

class _DonationMessage extends StatelessWidget {
  const _DonationMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
    color: Colors.white,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Icon(icon, size: 32, color: const Color(0xFF075B49)),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center),
          ?action,
        ],
      ),
    ),
  );
}

class _DonationModePill extends StatelessWidget {
  const _DonationModePill({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Semantics(
      button: true,
      selected: selected,
      label: 'Mode $title',
      child: Material(
        color: selected ? const Color(0xFF01543F) : Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: SizedBox(
            height: 48,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  title,
                  maxLines: 1,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : const Color(0xFF174B38),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

String _rupiah(int value) =>
    'Rp${value.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.')}';

String _compactRupiah(int value) => value >= 1000000
    ? 'Rp1.000.000'
    : value >= 100000
    ? 'Rp${value ~/ 1000} rb'
    : _rupiah(value);
