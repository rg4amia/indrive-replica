import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/app_tokens.dart';
import '../../core/map_canvas.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../shared/app_drawer.dart';
import 'rider_panels.dart';
import '../rider_controller.dart';
import 'search_page.dart';

class RiderHomePage extends StatelessWidget {
  const RiderHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<RiderController>();
    return Scaffold(
      drawer: const AppDrawer(),
      body: Obx(() {
        final phase = c.phase.value;
        final pins = <MapPin>[
          if (c.pickup.value != null) MapPin(PinKind.pickup, c.pickup.value!.lat, c.pickup.value!.lng),
          if (c.dropoff.value != null) MapPin(PinKind.dropoff, c.dropoff.value!.lat, c.dropoff.value!.lng),
        ];
        return Stack(children: [
          Positioned.fill(child: MapCanvas(pins: pins, path: c.route.value?.path ?? const [], bottomPadding: 280)),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.s4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Builder(builder: (ctx) => const MenuButton()),
                  const SizedBox(width: AppSpace.s3),
                  if (phase != RiderPhase.browse) Expanded(child: _RouteCard(c)),
                ]),
              ),
            ),
          ),
          Positioned(left: 0, right: 0, bottom: 0, child: _panelFor(phase, c)),
        ]);
      }),
    );
  }

  Widget _panelFor(RiderPhase phase, RiderController c) => switch (phase) {
        RiderPhase.browse => BrowsePanel(c),
        RiderPhase.planning => PlanningPanel(c),
        RiderPhase.searching => SearchingPanel(c),
        RiderPhase.ride => RidePanel(c),
        RiderPhase.rating => RatingPanel(c),
      };
}

class _RouteCard extends StatelessWidget {
  const _RouteCard(this.c);
  final RiderController c;

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final canEdit = c.phase.value == RiderPhase.planning;
    return Container(
      padding: const EdgeInsets.all(AppSpace.s3),
      decoration: BoxDecoration(color: p.bg, borderRadius: BorderRadius.circular(AppRadius.lg), boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 8, offset: Offset(0, 2))]),
      child: Column(children: [
        InfoRow(
          icon: Icons.person_pin_circle_outlined,
          title: c.pickup.value?.label ?? '',
          subtitle: c.pickup.value?.hint,
          onTap: canEdit
              ? () async {
                  final place = await Get.to<Place>(() => const SearchPage(editPickup: true));
                  if (place != null) await c.setPickup(place);
                }
              : null,
        ),
        InfoRow(
          icon: Icons.flag_outlined,
          title: c.dropoff.value?.label ?? '',
          subtitle: c.route.value == null ? null : '${distanceLabel(c.route.value!.distanceM)} · ${durationLabel(c.route.value!.durationS)}',
          onTap: canEdit
              ? () async {
                  final place = await Get.to<Place>(() => const SearchPage());
                  if (place != null) await c.setDestination(place);
                }
              : null,
        ),
      ]),
    );
  }
}
