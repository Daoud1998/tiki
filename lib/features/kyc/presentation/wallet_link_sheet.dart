// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';

// import '../../../core/i18n/tikki_tr.dart';
// import '../state/kyc_controller.dart';

// enum WalletProvider { bankily, masrvi }

// String walletProviderLabel(BuildContext context, WalletProvider p) {
//   switch (p) {
//     case WalletProvider.bankily:
//       return tikkiTr(context, ar: 'بنكيلي', fr: 'Bankily', en: 'Bankily');
//     case WalletProvider.masrvi:
//       return tikkiTr(context, ar: 'مصرفي', fr: 'Masrvi', en: 'Masrvi');
//   }
// }

// /// واجهة "Third‑Party" لربط محفظة (Bankily / Masrvi).
// /// - هذه واجهة جاهزة الآن.
// /// - لاحقاً تربط أزرار "إرسال الرمز" و "تأكيد" بـ API رسمي عند التعاقد.
// /// - حالياً: كود تجريبي ثابت 123456 لتسهيل الاختبار.
// class WalletLinkSheet extends ConsumerStatefulWidget {
//   const WalletLinkSheet({super.key, required this.provider});

//   final WalletProvider provider;

//   @override
//   ConsumerState<WalletLinkSheet> createState() => _WalletLinkSheetState();
// }

// class _WalletLinkSheetState extends ConsumerState<WalletLinkSheet> {
//   final _phone = TextEditingController();
//   final _otp = TextEditingController();

//   bool _consent = false;
//   bool _sent = false;
//   bool _busy = false;

//   static const _demoOtp = '123456';

//   @override
//   void dispose() {
//     _phone.dispose();
//     _otp.dispose();
//     super.dispose();
//   }

//   InputDecoration _fieldDec({
//     required String label,
//     String? hint,
//     IconData? icon,
//   }) {
//     final t = Theme.of(context);
//     final baseBorder = OutlineInputBorder(
//       borderRadius: BorderRadius.circular(14),
//       borderSide: BorderSide(color: t.colorScheme.outlineVariant),
//     );
//     return InputDecoration(
//       labelText: label,
//       hintText: hint,
//       filled: true,
//       fillColor: t.colorScheme.surfaceVariant,
//       prefixIcon: icon != null ? Icon(icon) : null,
//       border: baseBorder,
//       enabledBorder: baseBorder,
//       focusedBorder: baseBorder.copyWith(
//         borderSide: BorderSide(color: t.colorScheme.primary, width: 1.6),
//       ),
//       contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
//     );
//   }

//   Future<void> _sendOtp() async {
//     if (_busy) return;

//     final phone = _phone.text.trim();
//     if (phone.isEmpty) {
//       _toast(tikkiTr(context,
//           ar: 'أدخل رقم المحفظة',
//           fr: 'Entrez le numéro',
//           en: 'Enter the wallet number'));
//       return;
//     }
//     if (!_consent) {
//       _toast(tikkiTr(context,
//           ar: 'وافق على مشاركة بيانات التحقق',
//           fr: 'Acceptez le consentement',
//           en: 'Accept consent'));
//       return;
//     }

//     setState(() => _busy = true);

//     // TODO: اربط هنا بـ API رسمي عند التعاقد:
//     // await provider.startVerification(phone)
//     await Future<void>.delayed(const Duration(milliseconds: 500));

//     if (!mounted) return;
//     setState(() {
//       _busy = false;
//       _sent = true;
//     });

//     _toast(tikkiTr(
//       context,
//       ar: 'تم إرسال الرمز (للتجربة أدخل 123456)',
//       fr: 'Code envoyé (test: 123456)',
//       en: 'Code sent (demo: 123456)',
//     ));
//   }

//   Future<void> _confirmOtp() async {
//     if (_busy) return;

//     final code = _otp.text.trim();
//     if (code.length < 4) {
//       _toast(tikkiTr(context,
//           ar: 'أدخل رمز صحيح',
//           fr: 'Entrez un code valide',
//           en: 'Enter a valid code'));
//       return;
//     }

//     setState(() => _busy = true);

//     // TODO: اربط هنا بـ API رسمي عند التعاقد:
//     // await provider.confirm(code)
//     await Future<void>.delayed(const Duration(milliseconds: 500));

//     if (!mounted) return;
//     setState(() => _busy = false);

//     if (code != _demoOtp) {
//       _toast(tikkiTr(context,
//           ar: 'الرمز غير صحيح', fr: 'Code incorrect', en: 'Invalid code'));
//       return;
//     }

//     // نخزن الحالة محلياً عبر KYC controller (بدون ادعاء KYC كامل).
//     // يمكنك لاحقاً جعل policy تعتبر wallet_verified بمثابة approved حسب إعداد الأدمن.
//     await ref.read(kycControllerProvider.notifier).setStatus('wallet_verified');

//     if (!mounted) return;
//     Navigator.of(context).pop(true);
//   }

//   void _toast(String msg) {
//     ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
//   }

//   @override
//   Widget build(BuildContext context) {
//     final label = walletProviderLabel(context, widget.provider);

//     return SafeArea(
//       child: Padding(
//         padding: EdgeInsets.only(
//           left: 16,
//           right: 16,
//           top: 16,
//           bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
//         ),
//         child: Column(
//           mainAxisSize: MainAxisSize.min,
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Row(
//               children: [
//                 Expanded(
//                   child: Text(
//                     tikkiTr(context,
//                         ar: 'ربط محفظة $label',
//                         fr: 'Lier $label',
//                         en: 'Link $label'),
//                     style: Theme.of(context).textTheme.titleMedium,
//                   ),
//                 ),
//                 IconButton(
//                   onPressed: () => Navigator.of(context).pop(false),
//                   icon: const Icon(Icons.close),
//                 ),
//               ],
//             ),
//             const SizedBox(height: 8),
//             Text(
//               tikkiTr(
//                 context,
//                 ar: 'هذه واجهة جاهزة الآن. الربط الحقيقي يحتاج تكامل API رسمي مع $label.',
//                 fr: "Interface prête. L'intégration réelle nécessite un API officiel avec $label.",
//                 en: 'UI is ready. Real linking needs an official API integration with $label.',
//               ),
//               style: Theme.of(context).textTheme.bodySmall,
//             ),
//             const SizedBox(height: 14),
//             TextField(
//               controller: _phone,
//               keyboardType: TextInputType.phone,
//               decoration: _fieldDec(
//                 label: tikkiTr(context,
//                     ar: 'رقم المحفظة',
//                     fr: 'Numéro du wallet',
//                     en: 'Wallet number'),
//                 hint: tikkiTr(context,
//                     ar: 'مثال: 22xxxxxxxx',
//                     fr: 'Ex: 22xxxxxxxx',
//                     en: 'e.g. 22xxxxxxxx'),
//                 icon: Icons.phone_outlined,
//               ),
//             ),
//             const SizedBox(height: 10),
//             Row(
//               children: [
//                 Checkbox(
//                   value: _consent,
//                   onChanged: (v) => setState(() => _consent = v ?? false),
//                 ),
//                 Expanded(
//                   child: Text(
//                     tikkiTr(
//                       context,
//                       ar: 'أوافق على مشاركة بيانات التحقق مع مزود الخدمة فقط لغرض التوثيق.',
//                       fr: "J'accepte de partager les données de vérification uniquement pour la vérification.",
//                       en: 'I agree to share verification data with the provider for verification only.',
//                     ),
//                     style: Theme.of(context).textTheme.bodySmall,
//                   ),
//                 ),
//               ],
//             ),
//             const SizedBox(height: 10),
//             if (!_sent) ...[
//               SizedBox(
//                 width: double.infinity,
//                 child: FilledButton.icon(
//                   onPressed: _busy ? null : _sendOtp,
//                   icon: _busy
//                       ? const SizedBox(
//                           width: 16,
//                           height: 16,
//                           child: CircularProgressIndicator(strokeWidth: 2))
//                       : const Icon(Icons.sms_outlined),
//                   label: Text(tikkiTr(context,
//                       ar: 'إرسال رمز التحقق',
//                       fr: 'Envoyer le code',
//                       en: 'Send code')),
//                 ),
//               ),
//             ] else ...[
//               TextField(
//                 controller: _otp,
//                 keyboardType: TextInputType.number,
//                 decoration: InputDecoration(
//                   labelText: tikkiTr(context,
//                       ar: 'رمز التحقق', fr: 'Code', en: 'Code'),
//                 ),
//               ),
//               const SizedBox(height: 10),
//               SizedBox(
//                 width: double.infinity,
//                 child: FilledButton.icon(
//                   onPressed: _busy ? null : _confirmOtp,
//                   icon: _busy
//                       ? const SizedBox(
//                           width: 16,
//                           height: 16,
//                           child: CircularProgressIndicator(strokeWidth: 2))
//                       : const Icon(Icons.verified_outlined),
//                   label: Text(tikkiTr(context,
//                       ar: 'تأكيد وربط', fr: 'Confirmer', en: 'Confirm')),
//                 ),
//               ),
//               const SizedBox(height: 8),
//               Text(
//                 tikkiTr(context,
//                     ar: 'للاختبار: أدخل 123456',
//                     fr: 'Test: 123456',
//                     en: 'Demo: 123456'),
//                 style: Theme.of(context).textTheme.bodySmall,
//               ),
//             ],
//             const SizedBox(height: 8),
//           ],
//         ),
//       ),
//     );
//   }
// }
