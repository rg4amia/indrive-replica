import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gal/app_primitives.dart';
import 'package:gal/design_gallery.dart';

Widget host(Widget w, {Brightness b = Brightness.light}) =>
    MaterialApp(theme: appTheme(b), home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: w)));

void main() {
  test('formatMoney', () {
    expect(formatMoney(3450), '3 450 F CFA');
    expect(formatMoney(14600), '14 600 F CFA');
    expect(formatMoney(0), '0 F CFA');
  });

  testWidgets('stepper: minimum atteint', (t) async {
    var v = 2600;
    await t.pumpWidget(host(StatefulBuilder(builder: (c, set) =>
        PriceStepper(price: v, step: 100, min: 2500, onChanged: (n) => set(() => v = n)))));
    await t.tap(find.bySemanticsLabel(RegExp('Baisser')));
    await t.pump();
    expect(v, 2500);
    await t.tap(find.bySemanticsLabel(RegExp('Baisser')), warnIfMissed: false);
    await t.pump();
    expect(v, 2500);
  });

  testWidgets('offre expirée : accepter inactif', (t) async {
    var accepted = 0;
    final now = DateTime(2026, 1, 1, 12);
    var clock = now;
    await t.pumpWidget(host(OfferCard(
      price: 3800, etaMinutes: 3, driverName: 'Marcel', rating: 4.87, rides: 3477, vehicle: 'Suzuki S-Presso',
      expiresAt: now.add(const Duration(seconds: 10)), now: () => clock,
      onAccept: () => accepted++, onReject: () {},
    )));
    await t.tap(find.text('Accepter'));
    expect(accepted, 1);
    clock = now.add(const Duration(seconds: 11));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('Accepter'), warnIfMissed: false);
    expect(accepted, 1);
    expect(find.bySemanticsLabel(RegExp('offre expirée')), findsOneWidget);
  });

  testWidgets('bouton loading', (t) async {
    var n = 0;
    await t.pumpWidget(host(AppButton(label: 'Valider', loading: true, onPressed: () => n++)));
    await t.tap(find.byType(AppButton));
    expect(n, 0);
    expect(find.bySemanticsLabel('Valider, en cours'), findsOneWidget);
  });

  testWidgets('cibles >= 48 en clair et sombre', (t) async {
    for (final b in Brightness.values) {
      await t.pumpWidget(host(AppButton(label: 'A', onPressed: () {}, large: false), b: b));
      expect(t.getSize(find.byType(AppButton)).height, greaterThanOrEqualTo(48));
    }
  });
}
