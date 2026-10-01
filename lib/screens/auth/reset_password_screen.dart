import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/core/utils/validators.dart';
import 'package:cosmetix/providers/auth_provider.dart';
import 'package:cosmetix/widgets/custom_button.dart';
import 'package:cosmetix/widgets/custom_text_field.dart';

/// Added screen: sets a new password after the "reset link" step.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.email});

  final String email;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    final ok = await context.read<AuthProvider>().resetPassword(
      widget.email,
      _password.text,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (!ok) {
      showMessage(
        context,
        'Не удалось изменить пароль',
        type: MessageType.error,
      );
      return;
    }
    showMessage(
      context,
      'Пароль изменён. Войдите с новым паролем',
      type: MessageType.success,
    );
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                tooltip: 'Назад',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(
                  Icons.chevron_left,
                  color: AppColors.primaryDark,
                  size: 30,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Новый пароль',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Придумайте новый пароль для ${widget.email}.',
                      style: AppTextStyles.body.copyWith(
                        color: context.pal.subtext,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          CustomTextField(
                            label: 'Новый пароль',
                            hint: 'Минимум 8 символов, буквы и цифры',
                            controller: _password,
                            isPassword: true,
                            validator: Validators.password,
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 14),
                          CustomTextField(
                            label: 'Повторите пароль',
                            hint: '••••••••',
                            controller: _confirm,
                            isPassword: true,
                            validator: (v) =>
                                Validators.confirmPassword(v, _password.text),
                            onSubmitted: (_) => _save(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    CustomButton(
                      label: 'Сохранить пароль',
                      loading: _loading,
                      onPressed: _save,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
