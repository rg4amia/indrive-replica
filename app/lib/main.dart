import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'core/theme.dart';
import 'modules/app_controller.dart';
import 'modules/driver/driver_home_page.dart';
import 'modules/driver_controller.dart';
import 'modules/rider/home_page.dart';
import 'modules/rider_controller.dart';
import 'modules/shared/secondary_pages.dart';

void main() => runApp(const VtcApp());

/// Enregistre les contrôleurs ; séparé de main() pour que les tests puissent le rappeler.
void registerControllers({AppController? app}) {
  final a = Get.put<AppController>(app ?? AppController(), permanent: true);
  Get.put<RiderController>(RiderController(a), permanent: true);
  Get.put<DriverController>(DriverController(a), permanent: true);
}

class VtcApp extends StatelessWidget {
  const VtcApp({super.key, this.skipRegister = false});
  final bool skipRegister;

  @override
  Widget build(BuildContext context) {
    if (!skipRegister && !Get.isRegistered<AppController>()) registerControllers();
    return GetMaterialApp(
      title: 'VTC',
      debugShowCheckedModeBanner: false,
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      initialRoute: '/home',
      getPages: [
        GetPage(name: '/home', page: () => const RiderHomePage()),
        GetPage(name: '/driver', page: () => const DriverHomePage()),
        GetPage(name: '/history', page: () => const HistoryPage()),
        GetPage(name: '/wallet', page: () => const WalletPage()),
        GetPage(name: '/earnings', page: () => const StubPage(title: 'Mes revenus', ids: 'S25')),
        GetPage(name: '/notifications', page: () => const StubPage(title: 'Notifications', ids: 'S-notif')),
        GetPage(name: '/safety', page: () => const SafetyPage()),
        GetPage(name: '/settings', page: () => const StubPage(title: 'Paramètres', ids: 'S15')),
        GetPage(name: '/help', page: () => const StubPage(title: 'Aide', ids: 'S16')),
      ],
    );
  }
}
