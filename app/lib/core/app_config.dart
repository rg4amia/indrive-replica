/// Réglages de l'app. Le serveur de tuiles public d'OpenStreetMap est réservé aux essais :
/// pour la production, remplacer par un fournisseur de tuiles (voir replica/architecture.md).
class AppConfig {
  static String? tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const tileUserAgent = 'com.example.vtc_app';
  static const currency = 'F CFA';
  static const emergencyNumber = '112';
}
