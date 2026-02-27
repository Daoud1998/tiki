import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/localization/l10n.dart';
import '../../../core/state/auth_state.dart';

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
        return context.tr('auth.reset_password.error.weak_password');
      case 'requires_recent_login':
        return context.tr('auth.reset_password.error.requires_recent_login');
      case 'not_supported':
        return context.tr('auth.reset_password.error.not_supported');
      case 'not_signed_in':
        return context.tr('auth.reset_password.error.session_expired');
      case 'invalid_phone':
        return context.tr('auth.reset_password.error.invalid_phone');
      case 'email_in_use':
        return context.tr('auth.reset_password.error.phone_in_use');
      case 'network':
        return context.tr('auth.reset_password.error.network');
      case 'unauthenticated':
        return context.tr('auth.reset_password.error.unauthorized');
      default:
        if (kDebugMode && code != null && code.trim().isNotEmpty) {
          return context.tr(
            'auth.reset_password.error.generic_with_code',
            args: {'code': code},
          );
        }
        return context.tr('auth.reset_password.error.generic');
    }
  }

  Future<void> _submit() async {
    final p1 = _pass1.text.trim();
    final p2 = _pass2.text.trim();

    if (p1.length < 6) {
      _toast(context.tr('auth.reset_password.password_too_short'));
      return;
    }
    if (p1 != p2) {
      _toast(context.tr('auth.reset_password.password_mismatch'));
      return;
    }

    if (_busy) return;
    setState(() => _busy = true);

    try {
      final notifier = ref.read(authControllerProvider.notifier);

      // This method is added in auth_state.dart (see patch).
      final res = await notifier.setPhonePasswordAfterOtp(
        phoneE164: widget.phoneE164,
        newPassword: p1,
      );

      if (!mounted) return;

      if (!res.ok) {
        _toast(_errText(res.message));
        return;
      }

      _toast(context.tr('auth.reset_password.success'));
      Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('ResetPassword submit failed: $e');
      _toast(
        kDebugMode
            ? context.tr('auth.reset_password.error.unexpected_with',
                args: {'e': '$e'})
            : context.tr('common.error'),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('auth.reset_password.title')),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                context.tr(
                  'auth.reset_password.prompt',
                  args: {'phone': widget.phoneE164},
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _pass1,
                obscureText: !_show,
                decoration: InputDecoration(
                  labelText: context.tr('auth.reset_password.new_password'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pass2,
                obscureText: !_show,
                decoration: InputDecoration(
                  labelText: context.tr('auth.reset_password.confirm_password'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Checkbox(
                    value: _show,
                    onChanged: (v) => setState(() => _show = v ?? false),
                  ),
                  Text(context.tr('auth.reset_password.show_password')),
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
                    : Text(context.tr('common.save')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
