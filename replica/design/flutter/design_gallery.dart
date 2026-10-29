import 'package:flutter/material.dart';
import 'app_primitives.dart';
import 'app_tokens.dart';

ThemeData appTheme(Brightness b) {
  final palette = b == Brightness.light ? AppPalette.light : AppPalette.dark;
  return ThemeData(
    brightness: b,
    useMaterial3: true,
    scaffoldBackgroundColor: palette.bg,
    colorScheme: ColorScheme.fromSeed(seedColor: palette.accent, brightness: b).copyWith(
      surface: palette.bg,
      primary: palette.accent,
      onPrimary: palette.onAccent,
      error: palette.danger,
    ),
    extensions: [palette],
  );
}

/// Page de revue des primitives, en clair et en sombre : à lancer avec `flutter run -t lib/design_gallery.dart`.
void main() => runApp(const DesignGallery());

class DesignGallery extends StatelessWidget {
  const DesignGallery({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: appTheme(Brightness.light),
        darkTheme: appTheme(Brightness.dark),
        home: const _GalleryPage(),
      );
}

class _GalleryPage extends StatefulWidget {
  const _GalleryPage();
  @override
  State<_GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<_GalleryPage> {
  int price = 3450;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(AppSpace.s4), children: [
          PriceStepper(price: price, step: 100, min: 2500, onChanged: (v) => setState(() => price = v)),
          const SizedBox(height: AppSpace.s4),
          OfferCard(
            price: 3800, etaMinutes: 3, driverName: 'Marcel', rating: 4.87, rides: 3477,
            vehicle: 'Suzuki S-Presso', atYourPrice: true,
            expiresAt: DateTime.now().add(const Duration(seconds: 20)),
            onAccept: () {}, onReject: () {},
          ),
          const SizedBox(height: AppSpace.s4),
          AppButton(label: 'Chercher des offres', onPressed: () {}),
          const SizedBox(height: AppSpace.s2),
          AppButton(label: 'Annuler la commande', kind: AppButtonKind.danger, onPressed: () {}),
          const SizedBox(height: AppSpace.s2),
          const AppButton(label: 'Indisponible', onPressed: null, kind: AppButtonKind.secondary),
          const SizedBox(height: AppSpace.s2),
          AppButton(label: 'Chargement', loading: true, onPressed: () {}),
          const SizedBox(height: AppSpace.s4),
          const Wrap(spacing: AppSpace.s2, children: [
            StatusChip('Le conducteur a annulé', danger: true),
            StatusChip('Votre prix', icon: Icons.thumb_up_outlined),
          ]),
        ]),
      ),
    );
  }
}
