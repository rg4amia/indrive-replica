import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/app_primitives.dart';
import '../../core/app_tokens.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../driver_controller.dart';
import '../rider_controller.dart';

String _date(DateTime d) {
  const m = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
  return '${d.day} ${m[d.month - 1]}';
}

String _time(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// S12 : historique des courses.
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final c = Get.find<RiderController>();
  @override
  void initState() {
    super.initState();
    c.loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      appBar: AppBar(backgroundColor: p.bg, foregroundColor: p.text, elevation: 0, title: Text('Mes courses', style: AppText.title)),
      body: Obx(() {
        if (c.historyLoading.value) {
          return Padding(padding: const EdgeInsets.all(AppSpace.s4), child: Column(children: [for (var i = 0; i < 4; i++) const Padding(padding: EdgeInsets.only(bottom: AppSpace.s3), child: Skeleton(height: 72))]));
        }
        if (c.historyError.value != null) return Padding(padding: const EdgeInsets.all(AppSpace.s4), child: ErrorBanner(c.historyError.value!, onRetry: c.loadHistory));
        if (c.history.isEmpty) {
          return const Center(child: EmptyState(icon: Icons.receipt_long_outlined, title: "Pas encore de course", message: 'Vos courses terminées ou annulées apparaîtront ici.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpace.s4),
          itemCount: c.history.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpace.s2),
          itemBuilder: (_, i) {
            final r = c.history[i];
            final cancelled = r.status == RideStatus.cancelled;
            final byDriver = r.cancelledBy == 'driver';
            return Container(
              padding: const EdgeInsets.all(AppSpace.s3),
              decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(AppRadius.lg)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.request.pickup.label, style: AppText.small.copyWith(color: p.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(r.request.dropoff.label, style: AppText.label.copyWith(color: p.text), maxLines: 2, overflow: TextOverflow.ellipsis),
                    Text('${_date(r.createdAt)} · ${_time(r.createdAt)}', style: AppText.small.copyWith(color: p.textMuted)),
                    if (cancelled) Padding(padding: const EdgeInsets.only(top: AppSpace.s1), child: StatusChip(byDriver ? 'Le chauffeur a annulé' : 'Annulée', danger: true)),
                  ]),
                ),
                const SizedBox(width: AppSpace.s2),
                Text(formatMoney(cancelled ? 0 : (r.finalPrice ?? r.agreedPrice)), style: AppText.label.copyWith(color: p.text)),
              ]),
            );
          },
        );
      }),
    );
  }
}

/// S24 : solde et journal des commissions.
class WalletPage extends StatefulWidget {
  const WalletPage({super.key});
  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  final c = Get.find<DriverController>();
  @override
  void initState() {
    super.initState();
    c.loadWallet();
  }

  String _label(WalletKind k) => switch (k) {
        WalletKind.topup => 'Recharge',
        WalletKind.commission => 'Commission',
        WalletKind.refund => 'Remboursement',
        WalletKind.penalty => 'Pénalité',
      };

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      appBar: AppBar(backgroundColor: p.bg, foregroundColor: p.text, elevation: 0, title: Text('Solde et commissions', style: AppText.title)),
      body: Obx(() {
        final b = c.balance.value;
        return ListView(padding: const EdgeInsets.all(AppSpace.s4), children: [
          Text('Solde disponible', style: AppText.small.copyWith(color: p.textMuted)),
          Text(formatMoney(b), style: AppText.display.copyWith(color: b < 0 ? p.danger : p.text)),
          if (b < 0) Padding(padding: const EdgeInsets.only(top: AppSpace.s2), child: const ErrorBanner('Votre solde est négatif. Rechargez-le pour repasser en ligne.')),
          const SizedBox(height: AppSpace.s3),
          const AppButton(label: 'Recharger (bientôt)', onPressed: null, kind: AppButtonKind.secondary),
          const SizedBox(height: AppSpace.s4),
          Text('Mouvements', style: AppText.title.copyWith(color: p.text)),
          if (c.walletLoading.value)
            for (var i = 0; i < 3; i++) const Padding(padding: EdgeInsets.only(top: AppSpace.s3), child: Skeleton(height: 40))
          else if (c.wallet.isEmpty)
            const EmptyState(icon: Icons.receipt_long_outlined, title: 'Aucun mouvement')
          else
            for (final w in c.wallet)
              InfoRow(
                icon: w.amount < 0 ? Icons.south_east : Icons.north_east,
                title: _label(w.kind) + (w.pending ? ' (en attente)' : ''),
                subtitle: '${_date(w.createdAt)} · ${_time(w.createdAt)}',
                trailing: Text(formatMoney(w.amount), style: AppText.label.copyWith(color: w.amount < 0 ? p.danger : p.success)),
              ),
        ]);
      }),
    );
  }
}

/// Écrans annoncés dans l'inventaire mais pas encore construits : ils disent honnêtement ce qui manque.
class StubPage extends StatelessWidget {
  const StubPage({super.key, required this.title, required this.ids, this.child});
  final String title;
  final String ids;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      appBar: AppBar(backgroundColor: p.bg, foregroundColor: p.text, elevation: 0, title: Text(title, style: AppText.title)),
      body: ListView(padding: const EdgeInsets.all(AppSpace.s4), children: [
        EmptyState(icon: Icons.construction_outlined, title: 'Écran en préparation', message: "Cet écran ($ids) n'est pas encore construit. Voir replica/build-log.md."),
        ?child,
      ]),
    );
  }
}

/// S16 : sécurité. L'appel d'urgence réel nécessite `url_launcher` et un numéro par pays : ici, simple confirmation.
class SafetyPage extends StatelessWidget {
  const SafetyPage({super.key});
  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      appBar: AppBar(backgroundColor: p.bg, foregroundColor: p.text, elevation: 0, title: Text('Sécurité', style: AppText.title)),
      body: ListView(padding: const EdgeInsets.all(AppSpace.s4), children: [
        InfoRow(icon: Icons.contacts_outlined, title: "Contacts d'urgence", subtitle: 'Bientôt disponible'),
        InfoRow(icon: Icons.support_agent, title: 'Assistance', subtitle: 'Bientôt disponible'),
        const SizedBox(height: AppSpace.s4),
        Semantics(
          button: true,
          label: "Appeler les secours, numéro 112",
          excludeSemantics: true,
          child: Material(
            color: p.danger,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: () => showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text("Appeler le 112 ?"),
                  content: const Text("L'appel d'urgence depuis l'application n'est pas encore branché. En cas de danger, composez le 112 depuis votre téléphone."),
                  actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Compris'))],
                ),
              ),
              child: SizedBox(
                height: AppSize.buttonLg,
                child: Center(child: Text('Appeler le 112', style: AppText.label.copyWith(color: p.onDanger))),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
