import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:siaga_now_mobile/models/donation_campaign.dart';
import 'package:siaga_now_mobile/screens/donation_page.dart';
import 'package:siaga_now_mobile/services/donation_repository.dart';

class _StaticDonationRepository implements DonationRepository {
  const _StaticDonationRepository(this.campaigns);
  final List<DonationCampaign> campaigns;

  @override
  Future<List<DonationCampaign>> loadCampaigns() async => campaigns;
}

final _campaign = DonationCampaign(
  id: 7,
  title: 'Bantuan Tanggap Banjir',
  slug: 'bantuan-tanggap-banjir',
  description: 'Informasi program bantuan untuk warga terdampak.',
  organizer: 'Yayasan Contoh',
  targetAmount: 50000000,
  sourceName: 'Katalog SiagaNow',
  sourceUrl: null,
  verifiedAt: DateTime(2026, 11, 10),
);

void main() {
  testWidgets('empty donation catalog does not invent a program', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DonationPage(repository: _StaticDonationRepository([])),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Belum ada program donasi terverifikasi'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('Tidak ada transaksi'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Tidak ada transaksi'), findsOneWidget);
    expect(find.text('Donasi Sekarang'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('donation catalog and details fit small screens at large text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in [const Size(320, 640), const Size(360, 740)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(size),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: DonationPage(
            repository: _StaticDonationRepository([_campaign]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (
        var attempt = 0;
        attempt < 8 && find.text('Bantuan Tanggap Banjir').evaluate().isEmpty;
        attempt++
      ) {
        await tester.drag(
          find.byKey(const ValueKey('donation-catalog-list')),
          const Offset(0, -120),
        );
        await tester.pumpAndSettle();
      }
      expect(find.text('Bantuan Tanggap Banjir'), findsOneWidget);
      expect(find.text('Target Rp50.000.000'), findsOneWidget);
      expect(find.textContaining('Dana terkumpul'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.drag(
        find.byKey(const ValueKey('donation-catalog-list')),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lihat Informasi'));
      await tester.pumpAndSettle();
      expect(find.text('Informasi Donasi'), findsOneWidget);
      expect(find.text('Foto belum tersedia'), findsOneWidget);
      await tester.drag(find.byType(ListView).last, const Offset(0, -700));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('persentase tidak ditampilkan'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('donation requires login and payment remains unavailable', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(402, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var loginRequested = false;
    await tester.pumpWidget(
      MaterialApp(
        key: const ValueKey('donation-logged-out'),
        home: DonationPage(
          repository: _StaticDonationRepository([_campaign]),
          onLogin: () async => loginRequested = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lihat Informasi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Donasi Sekarang'));
    await tester.pumpAndSettle();
    expect(loginRequested, isTrue);
    expect(find.text('Donasi Sekarang'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        key: const ValueKey('donation-logged-in'),
        home: DonationPage(
          repository: _StaticDonationRepository([_campaign]),
          loggedIn: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lihat Informasi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Donasi Sekarang'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjutkan Pembayaran'));
    await tester.pumpAndSettle();
    expect(find.text('Nominal minimum Rp5.000.'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '2500');
    await tester.tap(find.text('Lanjutkan Pembayaran'));
    await tester.pumpAndSettle();
    expect(find.text('Nominal minimum Rp5.000.'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '5000');
    await tester.tap(find.text('Lanjutkan Pembayaran'));
    await tester.pumpAndSettle();
    expect(find.text('Metode pembayaran'), findsOneWidget);
    expect(find.textContaining('Nominal donasi Rp5.000'), findsOneWidget);
    final methodRows = tester.widgetList<ListTile>(find.byType(ListTile));
    expect(
      methodRows.where((row) => row.title is Text).length,
      greaterThanOrEqualTo(6),
    );
    expect(
      methodRows.where((row) => row.enabled == false).length,
      greaterThanOrEqualTo(6),
    );
    await tester.tap(find.text('Lanjutkan Pembayaran'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Pembayaran belum tersedia di versi ini. Tidak ada transaksi yang dibuat.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
