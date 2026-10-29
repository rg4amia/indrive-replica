import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/app_tokens.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../app_controller.dart';

/// S06 : choisir le départ ou l'arrivée. Renvoie le lieu choisi.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.editPickup = false});
  final bool editPickup;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _ctrl = TextEditingController();
  final app = Get.find<AppController>();
  List<Place> results = const [];
  bool loading = true;
  String? error;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _query('');
  }

  Future<void> _query(String q) async {
    final mine = ++_seq;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final r = await app.map.suggest(q);
      if (mine != _seq) return;
      setState(() {
        results = r;
        loading = false;
      });
    } catch (_) {
      if (mine != _seq) return;
      setState(() {
        loading = false;
        error = 'La recherche est indisponible. Vérifiez votre connexion.';
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: p.bg,
        foregroundColor: p.text,
        elevation: 0,
        title: Text(widget.editPickup ? 'Point de départ' : 'Où allez-vous ?', style: AppText.title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpace.s4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: _query,
            decoration: InputDecoration(
              labelText: widget.editPickup ? 'De' : 'À',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _ctrl.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Effacer',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _ctrl.clear();
                        _query('');
                      },
                    ),
              filled: true,
              fillColor: p.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: AppSpace.s3),
          if (error != null) ErrorBanner(error!, onRetry: () => _query(_ctrl.text)),
          Expanded(child: _results(p)),
        ]),
      ),
    );
  }

  Widget _results(dynamic p) {
    if (loading) {
      return Column(children: [for (var i = 0; i < 4; i++) const Padding(padding: EdgeInsets.symmetric(vertical: AppSpace.s3), child: Skeleton(height: 20))]);
    }
    if (results.isEmpty && error == null) {
      return const EmptyState(icon: Icons.location_off_outlined, title: 'Aucun lieu trouvé', message: "Essayez un quartier, une rue ou un lieu connu.");
    }
    return Semantics(
      liveRegion: true,
      label: '${results.length} résultats',
      child: ListView(children: [
        for (final r in results)
          InfoRow(icon: Icons.place_outlined, title: r.label, onTap: () => Get.back(result: r)),
      ]),
    );
  }
}
