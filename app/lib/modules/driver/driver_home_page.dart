import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/app_primitives.dart';
import '../../core/app_tokens.dart';
import '../../core/map_canvas.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../driver_controller.dart';
import '../shared/app_drawer.dart';

/// S19 à S22 : accueil chauffeur, demandes, contre-offre et course.
class DriverHomePage extends StatelessWidget {
  const DriverHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<DriverController>();
    final p = pal(context);
    return Scaffold(
      drawer: const AppDrawer(),
      body: Obx(() {
        final ride = c.ride.value;
        final pins = <MapPin>[
          if (ride != null) ...[
            MapPin(PinKind.pickup, ride.request.pickup.lat, ride.request.pickup.lng),
            MapPin(PinKind.dropoff, ride.request.dropoff.lat, ride.request.dropoff.lng),
          ],
        ];
        return Stack(children: [
          Positioned.fill(child: MapCanvas(pins: pins, bottomPadding: 280)),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.s4),
                child: Row(children: [
                  const MenuButton(),
                  const SizedBox(width: AppSpace.s3),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s3, vertical: AppSpace.s1),
                      decoration: BoxDecoration(
                        color: p.bg,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 8, offset: Offset(0, 2))],
                      ),
                      child: Row(children: [
                        Expanded(
                          child: Semantics(
                            label: 'Solde ${formatMoney(c.balance.value)}',
                            excludeSemantics: true,
                            child: Text('Solde ${formatMoney(c.balance.value)}',
                                style: AppText.label.copyWith(color: c.balance.value < 0 ? p.danger : p.text)),
                          ),
                        ),
                        Text(c.online.value ? 'En ligne' : 'Hors ligne', style: AppText.small.copyWith(color: p.textMuted)),
                        Switch(value: c.online.value, onChanged: ride != null ? null : c.toggleOnline),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ),
          Positioned(left: 0, right: 0, bottom: 0, child: ride != null ? _ActiveRidePanel(c, ride) : _RequestsPanel(c)),
        ]);
      }),
    );
  }
}

class _RequestsPanel extends StatelessWidget {
  const _RequestsPanel(this.c);
  final DriverController c;

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return BottomPanel(
      child: Obx(() {
        final list = c.requests;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (c.error.value != null) ...[ErrorBanner(c.error.value!), const SizedBox(height: AppSpace.s2)],
          if (!c.online.value)
            EmptyState(
              icon: Icons.power_settings_new,
              title: 'Vous êtes hors ligne',
              message: 'Passez en ligne pour voir les demandes de passagers autour de vous.',
              action: AppButton(label: 'Passer en ligne', onPressed: () => c.toggleOnline(true)),
            )
          else if (list.isEmpty)
            const EmptyState(
                icon: Icons.radar,
                title: 'Aucune demande à proximité',
                message: "Les nouvelles demandes apparaissent ici dès qu'un passager en publie une.")
          else ...[
            Text('${list.length} demande${list.length > 1 ? 's' : ''} près de vous', style: AppText.title.copyWith(color: p.text)),
            const SizedBox(height: AppSpace.s3),
            for (final r in list) ...[_RequestCard(c, r), const SizedBox(height: AppSpace.s3)],
          ],
        ]);
      }),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard(this.c, this.r);
  final DriverController c;
  final OpenRequest r;

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final req = r.request;
    return Obx(() {
      final sent = c.sentOffers.contains(req.id);
      final opts = [
        if (req.options['extra_passengers'] == true) 'Plus de 4 passagers',
        if (req.options['child_seat'] == true) 'Siège enfant',
      ];
      return Container(
        padding: const EdgeInsets.all(AppSpace.s4),
        decoration: BoxDecoration(color: p.surfaceRaised, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: p.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text(formatMoney(req.offeredPrice), style: AppText.price.copyWith(color: p.text)),
            const SizedBox(width: AppSpace.s2),
            Text('à ${distanceLabel(r.pickupDistanceM)}', style: AppText.title.copyWith(color: p.textMuted)),
          ]),
          const SizedBox(height: AppSpace.s2),
          InfoRow(icon: Icons.person_pin_circle_outlined, title: req.pickup.label),
          InfoRow(
              icon: Icons.flag_outlined,
              title: req.dropoff.label,
              subtitle: '${distanceLabel(req.distanceM)} · ${durationLabel(req.durationS)}'),
          Row(children: [
            Icon(Icons.star, size: 16, color: p.warning),
            const SizedBox(width: AppSpace.s1),
            Text('${r.riderName}  ${r.riderRating.toStringAsFixed(2).replaceAll('.', ',')}',
                style: AppText.small.copyWith(color: p.textMuted)),
          ]),
          if (opts.isNotEmpty || req.note != null) ...[
            const SizedBox(height: AppSpace.s2),
            Wrap(spacing: AppSpace.s2, children: [for (final o in opts) StatusChip(o), if (req.note != null) StatusChip(req.note!)]),
          ],
          const SizedBox(height: AppSpace.s3),
          if (sent)
            const Center(child: StatusChip('Offre envoyée, en attente du passager', icon: Icons.check))
          else
            Row(children: [
              Expanded(child: AppButton(label: 'Accepter', onPressed: () => c.offer(r, req.offeredPrice), large: false)),
              const SizedBox(width: AppSpace.s2),
              Expanded(
                  child: AppButton(
                      label: 'Contre-offre', kind: AppButtonKind.secondary, large: false, onPressed: () => _counter(context))),
            ]),
        ]),
      );
    });
  }

  Future<void> _counter(BuildContext context) async {
    final p = pal(context);
    final req = r.request;
    const step = 50;
    final max = req.offeredPrice * 130 ~/ 100;
    var price = req.offeredPrice + step;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.s4),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Proposer votre prix', style: AppText.title.copyWith(color: p.text)),
              const SizedBox(height: AppSpace.s1),
              Text("Le passager propose ${formatMoney(req.offeredPrice)}. Vous pouvez demander jusqu'à ${formatMoney(max)}.",
                  style: AppText.small.copyWith(color: p.textMuted)),
              const SizedBox(height: AppSpace.s4),
              PriceStepper(
                price: price,
                step: step,
                min: req.offeredPrice,
                onChanged: (v) => set(() => price = v > max ? max : v),
              ),
              const SizedBox(height: AppSpace.s4),
              AppButton(
                label: 'Envoyer mon offre',
                onPressed: () async {
                  await c.offer(r, price);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ActiveRidePanel extends StatelessWidget {
  const _ActiveRidePanel(this.c, this.ride);
  final DriverController c;
  final Ride ride;

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final (title, action, onTap) = switch (ride.status) {
      RideStatus.toPickup => ('En route vers le passager', 'Je suis là', c.arrived),
      RideStatus.arrived => ('Passager rejoint ?', 'Démarrer la course', c.start),
      RideStatus.inProgress => ('Course en cours', 'Terminer la course', c.complete),
      _ => ('', '', () async {}),
    };
    return BottomPanel(
      child: Obx(() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Semantics(liveRegion: true, child: Text(title, style: AppText.title.copyWith(color: p.text))),
            const SizedBox(height: AppSpace.s2),
            InfoRow(icon: Icons.person_pin_circle_outlined, title: ride.request.pickup.label),
            InfoRow(icon: Icons.flag_outlined, title: ride.request.dropoff.label),
            Row(children: [
              Expanded(child: Text('Prix convenu', style: AppText.body.copyWith(color: p.textMuted))),
              Text(formatMoney(ride.agreedPrice), style: AppText.price.copyWith(color: p.text)),
            ]),
            if (ride.status == RideStatus.toPickup)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.s1),
                child: Text(
                    'La commission de ${formatMoney(ride.commission)} est prélevée quand vous appuyez sur « Je suis là ».',
                    style: AppText.small.copyWith(color: p.textMuted)),
              ),
            if (ride.request.note != null)
              Padding(padding: const EdgeInsets.only(top: AppSpace.s2), child: StatusChip('Message : ${ride.request.note!}')),
            if (c.error.value != null) Padding(padding: const EdgeInsets.only(top: AppSpace.s2), child: ErrorBanner(c.error.value!)),
            const SizedBox(height: AppSpace.s4),
            AppButton(label: action, onPressed: onTap),
            if (ride.status == RideStatus.toPickup || ride.status == RideStatus.arrived) ...[
              const SizedBox(height: AppSpace.s2),
              AppButton(
                label: 'Annuler la course',
                kind: AppButtonKind.danger,
                onPressed: () async {
                  final reason = await pickReason(context, title: 'Pourquoi annuler ?', reasons: const [
                    ('passenger_no_show', "Le passager n'est pas venu"),
                    ('car_problem', 'Problème avec mon véhicule'),
                    ('too_far', 'Le point de départ est trop loin'),
                    ('other', 'Une autre raison'),
                  ]);
                  if (reason != null) await c.cancel(reason);
                },
              ),
            ],
          ])),
    );
  }
}
