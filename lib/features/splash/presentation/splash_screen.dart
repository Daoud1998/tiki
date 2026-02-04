import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Simple splash that forwards to Home after a short delay.
/// Keeps the app feeling fast and avoids landing on Search by mistake.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // A tiny pause so the logo is visible, then go to the main shell (/home).
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      context.go('/home');
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    String tr({required String ar, required String fr, required String en}) {
      final code = Localizations.localeOf(context).languageCode.toLowerCase();
      if (code == 'fr') return fr;
      if (code == 'en') return en;
      return ar;
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // If you have an asset logo later, replace this with Image.asset(...)
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.primary.withValues(alpha: 0.12),
                ),
                alignment: Alignment.center,
                child: Text(
                  'TIKI',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: cs.primary,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                tr(
                  ar: 'سوق موريتانيا في جيبك',
                  fr: 'Le marché de la Mauritanie dans votre poche',
                  en: 'Mauritania’s market in your pocket',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    cs.primary.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// import 'package:flutter/material.dart';
// import 'package:go_router/go_router.dart';

// import '../../../core/storage/local_store.dart';

// /// Simple splash that forwards to Home after a short delay.
// /// Keeps the app feeling fast and avoids landing on Search by mistake.
// class SplashScreen extends StatefulWidget {
//   const SplashScreen({super.key});

//   @override
//   State<SplashScreen> createState() => _SplashScreenState();
// }

// class _SplashScreenState extends State<SplashScreen> {
//   @override
//   void initState() {
//     super.initState();
//     // A tiny pause so the logo is visible, then go to the main shell (/home).
//     Future<void>.delayed(const Duration(milliseconds: 900), () async {
//       final store = await LocalStore.create();
//       final last = (store.getLastAppLocation() ?? '').trim();

//       String target = '/home';
//       if (last.isNotEmpty && last.startsWith('/')) {
//         // Avoid looping to splash/auth on cold start.
//         if (!last.startsWith('/splash') && !last.startsWith('/auth')) {
//           target = last;
//         }
//       }

//       if (!mounted) return;
//       context.go(target);
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     final cs = Theme.of(context).colorScheme;

//     String tr({required String ar, required String fr, required String en}) {
//       final code = Localizations.localeOf(context).languageCode.toLowerCase();
//       if (code == 'fr') return fr;
//       if (code == 'en') return en;
//       return ar;
//     }

//     return Scaffold(
//       backgroundColor: Theme.of(context).scaffoldBackgroundColor,
//       body: SafeArea(
//         child: Center(
//           child: Column(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               // If you have an asset logo later, replace this with Image.asset(...)
//               Container(
//                 width: 92,
//                 height: 92,
//                 decoration: BoxDecoration(
//                   shape: BoxShape.circle,
//                   color: cs.primary.withValues(alpha: 0.12),
//                 ),
//                 alignment: Alignment.center,
//                 child: Text(
//                   'TIKI',
//                   style: TextStyle(
//                     fontSize: 26,
//                     fontWeight: FontWeight.w900,
//                     color: cs.primary,
//                     letterSpacing: 1.2,
//                   ),
//                 ),
//               ),
//               const SizedBox(height: 14),
//               Text(
//                 tr(
//                   ar: 'سوق موريتانيا في جيبك',
//                   fr: 'Le marché de la Mauritanie dans votre poche',
//                   en: 'Mauritania’s market in your pocket',
//                 ),
//                 textAlign: TextAlign.center,
//                 style: TextStyle(
//                   fontWeight: FontWeight.w800,
//                   color: cs.onSurface.withValues(alpha: 0.85),
//                 ),
//               ),
//               const SizedBox(height: 10),
//               SizedBox(
//                 width: 26,
//                 height: 26,
//                 child: CircularProgressIndicator(
//                   strokeWidth: 2.6,
//                   valueColor: AlwaysStoppedAnimation<Color>(
//                     cs.primary.withValues(alpha: 0.85),
//                   ),
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }
