import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:siaga_now_mobile/main.dart';

void main() {
  testWidgets('SiagaNow menampilkan loading saat memulihkan sesi', (tester) async {
    await tester.pumpWidget(const SiagaNowApp());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
