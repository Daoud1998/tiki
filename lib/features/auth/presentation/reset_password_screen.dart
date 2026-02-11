import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tiki/core/state/auth_state.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({
    super.key,
    required this.phoneE164,
  });

  final String phoneE164;

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _pass1 = TextEditingController();
  final _pass2 = TextEditingController();
  bool _busy = false;
  bool _show = false;

  @override
  void dispose() {
    _pass1.dispose();
    _pass2.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  String _errText(String? code) {
    switch (code) {
      case 'weak_password':
        return 'كلمة المرور ضعيفة';
      case 'requires_recent_login':
        return 'أعد التحقق برمز OTP ثم حاول مرة أخرى';
      case 'not_supported':
        return 'هذا الحساب لا يدعم كلمة مرور للهاتف';
      case 'network':
        return 'تحقق من الإنترنت';
      default:
        return 'تعذر تغيير كلمة المرور';
    }
  }

  Future<void> _submit() async {
    final p1 = _pass1.text.trim();
    final p2 = _pass2.text.trim();

    if (p1.length < 6) {
      _toast('كلمة المرور قصيرة');
      return;
    }
    if (p1 != p2) {
      _toast('كلمتا المرور غير متطابقتين');
      return;
    }

    if (_busy) return;
    setState(() => _busy = true);

    try {
      final notifier = ref.read(authControllerProvider.notifier);

      // This method is added in auth_state.dart (see patch).
      final res = await (notifier as dynamic).setPhonePasswordAfterOtp(
        phoneE164: widget.phoneE164,
        newPassword: p1,
      );

      if (!mounted) return;

      if (res is AuthOpResult && !res.ok) {
        _toast(_errText(res.message));
        return;
      }

      _toast('تم تغيير كلمة المرور');
      Navigator.of(context).pop(true);
    } catch (e) {
      _toast('حدث خطأ');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تغيير كلمة المرور'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                'أدخل كلمة مرور جديدة لهذا الرقم:\n${widget.phoneE164}',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _pass1,
                obscureText: !_show,
                decoration: const InputDecoration(
                  labelText: 'كلمة المرور الجديدة',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pass2,
                obscureText: !_show,
                decoration: const InputDecoration(
                  labelText: 'تأكيد كلمة المرور',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Checkbox(
                    value: _show,
                    onChanged: (v) => setState(() => _show = v ?? false),
                  ),
                  const Text('إظهار كلمة المرور'),
                ],
              ),
              const Spacer(),
              FilledButton(
                onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('حفظ'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
