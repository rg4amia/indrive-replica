import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/app_primitives.dart';
import '../../core/app_tokens.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../services/map_service.dart';
import '../rider_controller.dart';
import 'search_page.dart';

const _cancelSearchReasons = <(String, String)>[
  ('drivers_too_far', 'Les chauffeurs sont trop loin'),
  ('price_too_high', 'Les prix proposés sont trop élevés'),
  ('accidental', "J'ai lancé la demande par erreur"),
  ('wrong_location', 'Le départ ou la destination est faux'),
  ('no_offers', "Aucun chauffeur n'a répondu"),
  ('other', 'Une autre raison'),
];

const _cancelRideReasons = <(String, String)>[
  ('changed_mind', "J'ai changé d'avis"),
  ('too_far', 'Le chauffeur est trop loin'),
  ('wrong_location', 'Le lieu de départ est faux'),
  ('other', 'Une autre raison'),
];

/// S05 : accueil, choix de la destination.
class BrowsePanel extends StatelessWidget {
  const BrowsePanel(this.c, {super.key});
  final RiderController c;

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final recents = FakeMapService.places.skip(1).take(4).toList();
    return BottomPanel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(
          button: true,
          label: 'Où allez-vous ? Choisir une destination',
          excludeSemantics: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: () async {
              final place = await Get.to<Place>(() => const SearchPage());
              if (place != null) await c.setDestination(place);
            },
            child: Container(
              height: AppSize.input,
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.s4),
              decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(AppRadius.md)),
              child: Row(children: [
                Icon(Icons.search, color: p.text),
                const SizedBox(width: AppSpace.s3),
                Expanded(child: Text('Où allez-vous, et pour combien ?', style: AppText.label.copyWith(color: p.text), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.s3),
        Obx(() => c.error.value == null ? const SizedBox.shrink() : ErrorBanner(c.error.value!)),
        for (final r in recents)
          InfoRow(icon: Icons.history, title: r.label, onTap: () => c.setDestination(r)),
      ]),
    );
  }
}

/// S07 : catégorie, prix proposé, options.
class PlanningPanel extends StatelessWidget {
  const PlanningPanel(this.c, {super.key});
  final RiderController c;

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return BottomPanel(
      child: Obx(() {
        if (c.routeLoading.value || c.route.value == null) {
          return Column(children: const [Skeleton(height: 72), SizedBox(height: AppSpace.s3), Skeleton(height: 48), SizedBox(height: AppSpace.s3), Skeleton(height: 56)]);
        }
        final cat = c.category.value;
        final tooLow = c.price.value < c.minPrice;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final k in Category.values) ...[
            _CategoryTile(c: c, category: k, selected: k == cat),
            const SizedBox(height: AppSpace.s2),
          ],
          const SizedBox(height: AppSpace.s2),
          PriceStepper(
            price: c.price.value,
            step: c.zone.priceStep,
            min: 0,
            onChanged: c.changePrice,
          ),
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.s1),
            child: Center(
              child: Text(
                tooLow ? 'Trop bas : minimum ${formatMoney(c.minPrice)}' : 'Tarif recommandé : ${formatMoney(c.recommendedFor(cat))}',
                style: AppText.small.copyWith(color: tooLow ? p.danger : p.textMuted),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.s2),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Accepter le chauffeur le plus proche à mon prix', style: AppText.body.copyWith(color: p.text)),
            value: c.autoAccept.value,
            onChanged: (v) => c.autoAccept.value = v,
          ),
          Obx(() => c.error.value == null ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(bottom: AppSpace.s2), child: ErrorBanner(c.error.value!))),
          Row(children: [
            Expanded(
              child: Obx(() => AppButton(
                    label: 'Chercher des offres',
                    loading: c.busy.value,
                    onPressed: tooLow ? null : c.search,
                  )),
            ),
            const SizedBox(width: AppSpace.s2),
            Semantics(
              button: true,
              label: 'Options de la course',
              excludeSemantics: true,
              child: Material(
                color: p.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  onTap: () => _options(context),
                  child: const SizedBox(width: AppSize.buttonLg, height: AppSize.buttonLg, child: Icon(Icons.tune)),
                ),
              ),
            ),
          ]),
        ]);
      }),
    );
  }

  void _options(BuildContext context) {
    final p = pal(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(AppSpace.s4, AppSpace.s4, AppSpace.s4, AppSpace.s4 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Obx(() => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text('Options', style: AppText.title.copyWith(color: p.text))),
                IconButton(tooltip: 'Fermer', onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
              ]),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Plus de 4 passagers'), value: c.extraPassengers.value, onChanged: (v) => c.extraPassengers.value = v),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text("Siège pour enfant"), value: c.childSeat.value, onChanged: (v) => c.childSeat.value = v),
              TextField(
                onChanged: (v) => c.note.value = v,
                maxLength: 140,
                decoration: InputDecoration(labelText: 'Message pour le chauffeur', filled: true, fillColor: p.surface, border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide.none)),
              ),
              AppButton(label: 'Terminé', onPressed: () => Navigator.pop(ctx)),
            ])),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.c, required this.category, required this.selected});
  final RiderController c;
  final Category category;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final price = c.recommendedFor(category);
    final minutes = (c.route.value!.durationS / 60).round();
    return Semantics(
      button: true,
      selected: selected,
      label: '${category.label}, environ ${formatMoney(price)}, ${category.tagline}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => c.selectCategory(category),
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSize.buttonLg),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.s3, vertical: AppSpace.s2),
          decoration: BoxDecoration(
            color: selected ? p.accentSoft : p.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: selected ? p.accent : Colors.transparent, width: 2),
          ),
          child: Row(children: [
            Icon(Icons.directions_car, color: selected ? p.onAccentSoft : p.textMuted),
            const SizedBox(width: AppSpace.s3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(category.label, style: AppText.label.copyWith(color: p.text)),
                Text('${category.tagline} · $minutes min', style: AppText.small.copyWith(color: p.textMuted)),
              ]),
            ),
            Text(formatMoney(price), style: AppText.label.copyWith(color: p.text)),
          ]),
        ),
      ),
    );
  }
}

/// S08 : recherche en cours et choix d'une offre.
class SearchingPanel extends StatelessWidget {
  const SearchingPanel(this.c, {super.key});
  final RiderController c;

  Future<void> _cancel(BuildContext context) async {
    final stop = await _confirmCancel(context);
    if (stop != true) return;
    if (!context.mounted) return;
    final reason = await pickReason(context, title: 'Pourquoi annuler ?', reasons: _cancelSearchReasons);
    if (reason != null) await c.cancelSearch(reason);
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return BottomPanel(
      child: Obx(() {
        final req = c.request.value;
        if (req == null) return const Skeleton(height: 120);
        final expired = c.expired;
        final offers = c.offers;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (expired) ...[
            EmptyState(
              icon: Icons.hourglass_empty,
              title: "Aucune offre pour l'instant",
              message: 'Les chauffeurs proches ne répondent pas à ${formatMoney(req.offeredPrice)}. Augmentez votre prix ou relancez la recherche.',
            ),
            AppButton(label: 'Relancer à ${formatMoney(req.offeredPrice + c.zone.raiseStep)}', onPressed: () => c.relaunch(raiseBy: c.zone.raiseStep)),
            const SizedBox(height: AppSpace.s2),
            AppButton(label: 'Relancer au même prix', kind: AppButtonKind.secondary, onPressed: () => c.relaunch()),
          ] else ...[
            Row(children: [
              Expanded(
                child: Text(
                  offers.isEmpty ? 'Nous cherchons des chauffeurs…' : '${offers.length} offre${offers.length > 1 ? 's' : ''} reçue${offers.length > 1 ? 's' : ''}',
                  style: AppText.title.copyWith(color: p.text),
                ),
              ),
              Semantics(label: '${c.remaining.value} secondes restantes', child: Text('${c.remaining.value} s', style: AppText.label.copyWith(color: p.textMuted))),
            ]),
            const SizedBox(height: AppSpace.s2),
            LinearProgressIndicator(
              value: (c.remaining.value / c.zone.requestTtl.inSeconds).clamp(0, 1).toDouble(),
              minHeight: 4,
              color: p.text,
              backgroundColor: p.surface,
            ),
            const SizedBox(height: AppSpace.s3),
            if (offers.isEmpty)
              Column(children: const [Skeleton(height: 120), SizedBox(height: AppSpace.s2), Skeleton(height: 16, width: 180)])
            else
              for (final o in offers) ...[
                OfferCard(
                  key: ValueKey(o.id),
                  price: o.price,
                  etaMinutes: o.etaMinutes,
                  driverName: o.driverName,
                  rating: o.rating,
                  rides: o.completedRides,
                  vehicle: o.vehicle,
                  atYourPrice: o.price == req.offeredPrice,
                  expiresAt: o.expiresAt,
                  onAccept: () => c.choose(o),
                  onReject: () => c.reject(o),
                ),
                const SizedBox(height: AppSpace.s3),
              ],
            Obx(() => c.error.value == null ? const SizedBox.shrink() : ErrorBanner(c.error.value!)),
            const SizedBox(height: AppSpace.s2),
            Row(children: [
              IconButton.filledTonal(
                tooltip: 'Baisser de ${formatMoney(c.zone.raiseStep)} (impossible)',
                onPressed: null,
                icon: const Icon(Icons.remove),
              ),
              Expanded(child: Center(child: Text(formatMoney(req.offeredPrice), style: AppText.price.copyWith(color: p.text)))),
              IconButton.filledTonal(
                tooltip: 'Augmenter de ${formatMoney(c.zone.raiseStep)}',
                onPressed: c.raisePrice,
                icon: const Icon(Icons.add),
              ),
            ]),
            if (req.autoAccept)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.s1),
                child: Center(child: Text('Le premier chauffeur à ce prix sera accepté automatiquement.', style: AppText.small.copyWith(color: p.textMuted), textAlign: TextAlign.center)),
              ),
          ],
          const SizedBox(height: AppSpace.s3),
          AppButton(label: 'Annuler la demande', kind: AppButtonKind.danger, onPressed: () => _cancel(context)),
        ]);
      }),
    );
  }
}

Future<bool?> _confirmCancel(BuildContext context) {
  final p = pal(context);
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: p.bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s4),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Annuler votre demande ?', style: AppText.title.copyWith(color: p.text)),
          const SizedBox(height: AppSpace.s4),
          AppButton(label: 'Continuer la recherche', onPressed: () => Navigator.pop(ctx, false)),
          const SizedBox(height: AppSpace.s2),
          AppButton(label: 'Oui, annuler', kind: AppButtonKind.danger, onPressed: () => Navigator.pop(ctx, true)),
        ]),
      ),
    ),
  );
}

/// S09 et S10 : chauffeur en route, course en cours, ou course annulée.
class RidePanel extends StatelessWidget {
  const RidePanel(this.c, {super.key});
  final RiderController c;

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return BottomPanel(
      child: Obx(() {
        final r = c.ride.value;
        if (r == null) return const Skeleton(height: 120);
        if (r.status == RideStatus.cancelled) {
          final byDriver = r.cancelledBy == 'driver';
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            EmptyState(
              icon: Icons.cancel_outlined,
              title: byDriver ? 'Le chauffeur a annulé' : 'Course annulée',
              message: byDriver ? 'Aucun frais ne vous est facturé. Vous pouvez relancer une demande.' : null,
            ),
            AppButton(label: 'Faire une nouvelle demande', onPressed: c.reset),
          ]);
        }
        final title = switch (r.status) {
          RideStatus.toPickup => 'Votre chauffeur arrive',
          RideStatus.arrived => 'Votre chauffeur est là',
          RideStatus.inProgress => 'Course en cours',
          _ => '',
        };
        final cancellable = r.status == RideStatus.toPickup || r.status == RideStatus.arrived;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Semantics(liveRegion: true, child: Text(title, style: AppText.title.copyWith(color: p.text))),
          const SizedBox(height: AppSpace.s3),
          Row(children: [
            CircleAvatar(radius: AppSize.avatarMd / 2, backgroundColor: p.surface, child: Text(r.driverName.characters.first, style: AppText.title.copyWith(color: p.text))),
            const SizedBox(width: AppSpace.s3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.driverName, style: AppText.label.copyWith(color: p.text)),
                Text('${r.vehicle} · ${r.plate}', style: AppText.small.copyWith(color: p.textMuted)),
              ]),
            ),
            Text(formatMoney(r.agreedPrice), style: AppText.price.copyWith(color: p.text)),
          ]),
          const SizedBox(height: AppSpace.s4),
          if (r.status == RideStatus.toPickup && !r.passengerOnWay)
            AppButton(label: "J'arrive au point de rendez-vous", kind: AppButtonKind.secondary, onPressed: c.passengerOnWay),
          if (r.passengerOnWay && r.status != RideStatus.inProgress)
            Center(child: StatusChip('Chauffeur prévenu : vous arrivez', icon: Icons.check)),
          Obx(() => c.error.value == null ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(top: AppSpace.s2), child: ErrorBanner(c.error.value!))),
          if (cancellable) ...[
            const SizedBox(height: AppSpace.s2),
            AppButton(
              label: 'Annuler la course',
              kind: AppButtonKind.danger,
              onPressed: () async {
                final reason = await pickReason(context, title: 'Pourquoi annuler ?', reasons: _cancelRideReasons);
                if (reason != null) await c.cancelRide(reason);
              },
            ),
          ],
        ]);
      }),
    );
  }
}

/// S11 : prix final et note du chauffeur.
class RatingPanel extends StatelessWidget {
  const RatingPanel(this.c, {super.key});
  final RiderController c;

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return BottomPanel(
      child: Obx(() {
        final r = c.ride.value;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Course terminée', style: AppText.title.copyWith(color: p.text), textAlign: TextAlign.center),
          const SizedBox(height: AppSpace.s2),
          Text(formatMoney(r?.finalPrice ?? r?.agreedPrice ?? 0), style: AppText.display.copyWith(color: p.text), textAlign: TextAlign.center),
          Text('À régler au chauffeur en espèces', style: AppText.small.copyWith(color: p.textMuted), textAlign: TextAlign.center),
          const SizedBox(height: AppSpace.s4),
          Text('Comment s\'est passée la course avec ${r?.driverName ?? 'votre chauffeur'} ?', style: AppText.body.copyWith(color: p.text), textAlign: TextAlign.center),
          StarsInput(value: c.stars.value, onChanged: (v) => c.stars.value = v),
          const SizedBox(height: AppSpace.s3),
          AppButton(label: c.stars.value == 0 ? 'Passer' : 'Envoyer ma note', onPressed: c.submitRating),
        ]);
      }),
    );
  }
}
