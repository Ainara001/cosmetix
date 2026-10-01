import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/core/utils/validators.dart';
import 'package:cosmetix/providers/auth_provider.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/widgets/common_widgets.dart';
import 'package:cosmetix/widgets/custom_button.dart';
import 'package:cosmetix/widgets/custom_text_field.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final exists = await context.read<AuthProvider>().emailExists(_email.text);
    if (!mounted) return;
    if (!exists) {
      setState(() {
        _loading = false;
        _error = tr('Аккаунт с таким email не найден');
      });
      return;
    }
    setState(() => _loading = false);
    // No server: the "e-mail" is simulated and the user continues locally.
    await infoDialog(
      context,
      title: tr('Ссылка отправлена'),
      message: trf(
        'Мы отправили ссылку для восстановления на {v0}.\n\nПриложение работает без сервера, поэтому письмо имитируется: на следующем экране задайте новый пароль.',
        {'v0': _email.text.trim()},
      ),
    );
    if (!mounted) return;
    Navigator.pushReplacementNamed(
      context,
      AppRoutes.resetPassword,
      arguments: _email.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                tooltip: tr('Назад'),
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
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      decoration: const BoxDecoration(
                        color: AppColors.primarySoft,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.vpn_key_outlined,
                        size: 36,
                        color: AppColors.primaryDark,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      tr('Забыли пароль?'),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr(
                        'Введите email, указанный при регистрации, и мы отправим ссылку для восстановления доступа.',
                      ),
                      textAlign: TextAlign.center,
                      style: AppTextStyles.small.copyWith(color: pal.subtext),
                    ),
                    const SizedBox(height: 20),
                    Form(
                      key: _formKey,
                      child: CustomTextField(
                        label: 'Email',
                        hint: 'example@mail.com',
                        controller: _email,
                        validator: Validators.email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: AppColors.danger,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                    CustomButton(
                      label: tr('Отправить ссылку'),
                      loading: _loading,
                      onPressed: _send,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          tr('Вспомнили пароль?'),
                          style: AppTextStyles.small.copyWith(
                            color: pal.subtext,
                          ),
                        ),
                        LinkText(
                          tr('Вернуться к входу'),
                          onTap: () => Navigator.of(context).maybePop(),
                        ),
                      ],
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
