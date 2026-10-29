import 'package:flutter/material.dart';

import '../data/models.dart';
import 'app_tokens.dart';
import 'theme.dart';

/// Feuille inférieure posée sur la carte (RouteSheet de replica/design/components.md).
class BottomPanel extends StatelessWidget {
  const BottomPanel({super.key, required this.child, this.maxHeightFactor = 0.85});
  final Widget child;
  final double maxHeightFactor;

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * maxHeightFactor),
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
        boxShadow: const [BoxShadow(color: Color(0x24000000), blurRadius: 24, offset: Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: AppSpace.s2),
          Container(width: 36, height: 4, decoration: BoxDecoration(color: p.border, borderRadius: BorderRadius.circular(2))),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(AppSpace.s4, AppSpace.s3, AppSpace.s4, AppSpace.s4),
              child: child,
            ),
          ),
        ]),
      ),
    );
  }
}

class Skeleton extends StatelessWidget {
  const Skeleton({super.key, this.height = 16, this.width});
  final double height;
  final double? width;
  @override
  Widget build(BuildContext context) => Container(
        height: height,
        width: width,
        decoration: BoxDecoration(color: pal(context).surface, borderRadius: BorderRadius.circular(AppRadius.sm)),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpace.s5),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 40, color: p.textMuted),
        const SizedBox(height: AppSpace.s3),
        Text(title, style: AppText.title.copyWith(color: p.text), textAlign: TextAlign.center),
        if (message != null) ...[
          const SizedBox(height: AppSpace.s2),
          Text(message!, style: AppText.body.copyWith(color: p.textMuted), textAlign: TextAlign.center),
        ],
        if (action != null) ...[const SizedBox(height: AppSpace.s4), action!],
      ]),
    );
  }
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpace.s3),
        decoration: BoxDecoration(color: p.dangerSoft, borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Row(children: [
          Icon(Icons.error_outline, color: p.danger),
          const SizedBox(width: AppSpace.s2),
          Expanded(child: Text(message, style: AppText.small.copyWith(color: p.danger))),
          if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Réessayer')),
        ]),
      ),
    );
  }
}

/// Ligne « icône – libellé – valeur » (ListRow de replica/design/components.md).
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.icon, required this.title, this.subtitle, this.trailing, this.onTap, this.badge});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Semantics(
      button: onTap != null,
      label: [title, if (subtitle != null) subtitle!, if (badge != null && badge! > 0) '$badge non lues'].join(', '),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSize.tapMin),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.s2),
            child: Row(children: [
              Icon(icon, color: p.textMuted),
              const SizedBox(width: AppSpace.s3),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: AppText.body.copyWith(color: p.text), maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (subtitle != null) Text(subtitle!, style: AppText.small.copyWith(color: p.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              if (badge != null && badge! > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.s2, vertical: 2),
                  decoration: BoxDecoration(color: p.danger, borderRadius: BorderRadius.circular(AppRadius.pill)),
                  child: Text('$badge', style: AppText.caption.copyWith(color: p.onDanger)),
                ),
              if (trailing != null) trailing!,
            ]),
          ),
        ),
      ),
    );
  }
}

/// Saisie des étoiles : chaque étoile mesure 48 dp.
class StarsInput extends StatelessWidget {
  const StarsInput({super.key, required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      for (var i = 1; i <= 5; i++)
        Semantics(
          button: true,
          selected: i <= value,
          label: '$i sur 5',
          excludeSemantics: true,
          child: InkResponse(
            onTap: () => onChanged(i),
            child: SizedBox(
              width: AppSize.tapMin,
              height: AppSize.tapMin,
              child: Icon(i <= value ? Icons.star : Icons.star_border, size: 36, color: i <= value ? p.warning : p.textMuted),
            ),
          ),
        ),
    ]);
  }
}

/// Liste de motifs en feuille modale ; renvoie le code choisi.
Future<String?> pickReason(BuildContext context, {required String title, required List<(String code, String label)> reasons}) {
  final p = pal(context);
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: p.bg,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet))),
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s4),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title, style: AppText.title.copyWith(color: p.text))),
            IconButton(tooltip: 'Fermer', onPressed: () => Navigator.pop(c), icon: const Icon(Icons.close)),
          ]),
          for (final r in reasons)
            InfoRow(icon: Icons.chevron_right, title: r.$2, onTap: () => Navigator.pop(c, r.$1)),
        ]),
      ),
    ),
  );
}

String durationLabel(int seconds) {
  final m = (seconds / 60).round();
  if (m < 60) return '$m min';
  return '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')}';
}

String distanceLabel(int meters) => meters < 1000 ? '$meters m' : '${(meters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';

String errorMessage(Object e) {
  final code = e is RideException ? e.code : '$e';
  const map = {
    'request_already_open': 'Vous avez déjà une demande en cours.',
    'ride_already_active': 'Vous avez déjà une course en cours.',
    'price_too_low': 'Ce prix est trop bas pour ce trajet. Augmentez-le.',
    'offer_not_available': "Cette offre n'est plus disponible.",
    'driver_busy': 'Ce chauffeur vient de prendre une autre course.',
    'request_not_open': "Cette demande n'est plus ouverte.",
    'price_out_of_band': 'Votre prix doit rester entre le prix du passager et 30 % au-dessus.',
    'balance_too_low': 'Votre solde est insuffisant. Rechargez-le pour continuer.',
    'driver_not_ready': 'Passez en ligne pour envoyer une offre.',
  };
  for (final k in map.keys) {
    if (code.contains(k)) return map[k]!;
  }
  return "Une erreur est survenue. Réessayez dans un instant.";
}
