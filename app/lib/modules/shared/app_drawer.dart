import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/app_tokens.dart';
import '../../core/app_primitives.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../app_controller.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final app = Get.find<AppController>();
    final p = pal(context);
    final isRider = app.mode.value == AppMode.rider;
    void go(String route) {
      Navigator.pop(context);
      Get.toNamed(route);
    }

    return Drawer(
      child: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(AppSpace.s4),
            child: Row(children: [
              CircleAvatar(radius: AppSize.avatarMd / 2, backgroundColor: p.surface, child: Icon(Icons.person, color: p.textMuted)),
              const SizedBox(width: AppSpace.s3),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(isRider ? 'Mon profil' : 'Profil chauffeur', style: AppText.label.copyWith(color: p.text)),
                  Row(children: [
                    Icon(Icons.star, size: 16, color: p.warning),
                    const SizedBox(width: AppSpace.s1),
                    Text('4,96 (11)', style: AppText.small.copyWith(color: p.textMuted)),
                  ]),
                ]),
              ),
            ]),
          ),
          Divider(height: 1, color: p.border),
          Expanded(
            child: ListView(padding: const EdgeInsets.symmetric(horizontal: AppSpace.s4), children: [
              if (isRider) ...[
                InfoRow(icon: Icons.directions_car_outlined, title: 'Réserver une course', onTap: () => Navigator.pop(context)),
                InfoRow(icon: Icons.history, title: 'Mes courses', onTap: () => go('/history')),
              ] else ...[
                InfoRow(icon: Icons.map_outlined, title: 'Demandes', onTap: () => Navigator.pop(context)),
                InfoRow(icon: Icons.account_balance_wallet_outlined, title: 'Solde et commissions', onTap: () => go('/wallet')),
                InfoRow(icon: Icons.bar_chart, title: 'Mes revenus', onTap: () => go('/earnings')),
              ],
              Obx(() => InfoRow(icon: Icons.notifications_none, title: 'Notifications', badge: app.unreadNotifications.value, onTap: () => go('/notifications'))),
              InfoRow(icon: Icons.shield_outlined, title: 'Sécurité', onTap: () => go('/safety')),
              InfoRow(icon: Icons.settings_outlined, title: 'Paramètres', onTap: () => go('/settings')),
              InfoRow(icon: Icons.info_outline, title: 'Aide', onTap: () => go('/help')),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpace.s4),
            child: AppButton(
              label: isRider ? 'Passer en mode chauffeur' : 'Passer en mode passager',
              onPressed: () {
                Navigator.pop(context);
                app.switchMode(isRider ? AppMode.driver : AppMode.rider);
              },
            ),
          ),
        ]),
      ),
    );
  }
}

/// Bouton rond posé sur la carte pour ouvrir le menu.
class MenuButton extends StatelessWidget {
  const MenuButton({super.key});
  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Semantics(
      button: true,
      label: 'Ouvrir le menu',
      excludeSemantics: true,
      child: Material(
        color: p.bg,
        shape: const CircleBorder(),
        elevation: 2,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => Scaffold.of(context).openDrawer(),
          child: const SizedBox(width: AppSize.tapMin, height: AppSize.tapMin, child: Icon(Icons.menu)),
        ),
      ),
    );
  }
}
