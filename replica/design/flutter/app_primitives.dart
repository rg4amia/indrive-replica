import 'dart:async';
import 'package:flutter/material.dart';
import 'app_tokens.dart';

AppPalette _p(BuildContext c) => Theme.of(c).extension<AppPalette>()!;

enum AppButtonKind { primary, secondary, ghost, danger }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = AppButtonKind.primary,
    this.loading = false,
    this.large = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonKind kind;
  final bool loading;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final p = _p(context);
    final (bg, fg) = switch (kind) {
      AppButtonKind.primary => (p.accent, p.onAccent),
      AppButtonKind.secondary => (p.surface, p.text),
      AppButtonKind.ghost => (Colors.transparent, p.accent),
      AppButtonKind.danger => (p.dangerSoft, p.danger),
    };
    final enabled = onPressed != null && !loading;
    return Semantics(
      button: true,
      enabled: enabled,
      label: loading ? '$label, en cours' : label,
      excludeSemantics: true,
      child: Opacity(
        opacity: onPressed == null ? 0.4 : 1,
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: enabled ? onPressed : null,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: large ? AppSize.buttonLg : AppSize.buttonMd,
                minWidth: AppSize.tapMin,
              ),
              child: Center(
                child: loading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                      )
                    : Text(label, style: AppText.label.copyWith(color: fg)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Montant en francs avec espace insécable : 3450 -> « 3 450 F CFA ».
String formatMoney(int amount, {String currency = 'F CFA'}) {
  final s = amount.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return '${amount < 0 ? '-' : ''}$b $currency';
}

class PriceStepper extends StatelessWidget {
  const PriceStepper({
    super.key,
    required this.price,
    required this.step,
    required this.min,
    required this.onChanged,
    this.locked = false,
  });

  final int price;
  final int step;
  final int min;
  final ValueChanged<int> onChanged;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final p = _p(context);
    Widget round(String semantic, IconData icon, int? next) => Semantics(
          button: true,
          enabled: next != null,
          label: semantic,
          excludeSemantics: true,
          child: Opacity(
            opacity: next == null ? 0.4 : 1,
            child: Material(
              color: p.surfaceRaised,
              shape: CircleBorder(side: BorderSide(color: p.border)),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: next == null ? null : () => onChanged(next),
                child: SizedBox(
                  width: AppSize.tapMin,
                  height: AppSize.tapMin,
                  child: Icon(icon, color: p.text),
                ),
              ),
            ),
          ),
        );

    final canDown = !locked && price - step >= min;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        round('Baisser de ${formatMoney(step)}', Icons.remove, canDown ? price - step : null),
        Semantics(
          liveRegion: true,
          label: formatMoney(price),
          excludeSemantics: true,
          child: Text(formatMoney(price), style: AppText.price.copyWith(color: p.text)),
        ),
        round('Monter de ${formatMoney(step)}', Icons.add, locked ? null : price + step),
      ],
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.danger = false, this.icon});
  final String label;
  final bool danger;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = _p(context);
    final bg = danger ? p.dangerSoft : p.accentSoft;
    final fg = danger ? p.danger : p.onAccentSoft;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s2, vertical: AppSpace.s1),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: AppSpace.s1)],
        Text(label, style: AppText.caption.copyWith(color: fg)),
      ]),
    );
  }
}

/// Carte d'offre d'un chauffeur. Le minuteur est aussi exposé en texte (pas seulement en couleur).
class OfferCard extends StatefulWidget {
  const OfferCard({
    super.key,
    required this.price,
    required this.etaMinutes,
    required this.driverName,
    required this.rating,
    required this.rides,
    required this.vehicle,
    required this.expiresAt,
    required this.onAccept,
    required this.onReject,
    this.atYourPrice = false,
    this.avatar,
    this.now,
  });

  final int price;
  final int etaMinutes;
  final String driverName;
  final double rating;
  final int rides;
  final String vehicle;
  final DateTime expiresAt;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final bool atYourPrice;
  final Widget? avatar;
  final DateTime Function()? now; // injectable pour les tests

  @override
  State<OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends State<OfferCard> {
  late final Timer _tick;
  late final DateTime _start = _now();
  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  double get _progress {
    final total = widget.expiresAt.difference(_start).inMilliseconds;
    if (total <= 0) return 1;
    return (_now().difference(_start).inMilliseconds / total).clamp(0.0, 1.0);
  }

  bool get _expired => !_now().isBefore(widget.expiresAt);

  @override
  Widget build(BuildContext context) {
    final p = _p(context);
    final left = widget.expiresAt.difference(_now()).inSeconds.clamp(0, 999);
    final summary = '${formatMoney(widget.price)}, ${widget.etaMinutes} minutes, ${widget.driverName}, '
        'note ${widget.rating.toStringAsFixed(2)} sur ${widget.rides} courses, ${widget.vehicle}'
        '${_expired ? ', offre expirée' : ', expire dans $left secondes'}';
    return Semantics(
      container: true,
      label: summary,
      child: ExcludeSemantics(
        excluding: false,
        child: Opacity(
          opacity: _expired ? 0.5 : 1,
          child: Container(
            padding: const EdgeInsets.all(AppSpace.s4),
            decoration: BoxDecoration(
              color: p.surfaceRaised,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 2))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Text(formatMoney(widget.price), style: AppText.price.copyWith(color: p.text)),
                const SizedBox(width: AppSpace.s2),
                Text('${widget.etaMinutes} min', style: AppText.title.copyWith(color: p.textMuted)),
              ]),
              if (widget.atYourPrice) ...[
                const SizedBox(height: AppSpace.s2),
                const Align(alignment: Alignment.centerLeft, child: StatusChip('Votre prix', icon: Icons.thumb_up_outlined)),
              ],
              const SizedBox(height: AppSpace.s3),
              Row(children: [
                widget.avatar ?? CircleAvatar(radius: AppSize.avatarSm / 2, backgroundColor: p.surface,
                    child: Text(widget.driverName.characters.first, style: AppText.label.copyWith(color: p.text))),
                const SizedBox(width: AppSpace.s3),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${widget.driverName}  ★ ${widget.rating.toStringAsFixed(2)}  ${widget.rides} courses',
                        style: AppText.body.copyWith(color: p.text), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(widget.vehicle, style: AppText.small.copyWith(color: p.textMuted)),
                  ]),
                ),
              ]),
              const SizedBox(height: AppSpace.s4),
              Row(children: [
                Expanded(child: AppButton(label: 'Refuser', kind: AppButtonKind.secondary, large: false,
                    onPressed: _expired ? null : widget.onReject)),
                const SizedBox(width: AppSpace.s2),
                Expanded(child: _TimerAcceptButton(progress: _progress, enabled: !_expired, onPressed: widget.onAccept)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class _TimerAcceptButton extends StatelessWidget {
  const _TimerAcceptButton({required this.progress, required this.enabled, required this.onPressed});
  final double progress;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final p = _p(context);
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Accepter',
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Material(
            color: p.accent,
            child: InkWell(
              onTap: enabled ? onPressed : null,
              child: SizedBox(
                height: AppSize.buttonMd,
                child: Stack(children: [
                  // la zone « consommée » s'assombrit de gauche à droite ; le libellé reste lisible
                  Positioned.fill(
                    child: FractionallySizedBox(
                      alignment: Alignment.centerRight,
                      widthFactor: progress,
                      child: ColoredBox(color: p.onAccent.withValues(alpha: 0.18)),
                    ),
                  ),
                  Center(child: Text('Accepter', style: AppText.label.copyWith(color: p.onAccent))),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
