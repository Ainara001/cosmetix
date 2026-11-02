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

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    // The code is shown for any e-mail so the screen does not reveal which
    // addresses are registered; it only works for a real account.
    final code = await context.read<AuthProvider>().requestResetCode(
      _email.text,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    // No server: the "e-mail" is simulated and the user continues locally.
    await infoDialog(
      context,
      title: tr('Код отправлен'),
      message: trf(
        'Мы отправили код подтверждения на {v0}.\n\nПриложение работает без сервера, поэтому письмо имитируется. Ваш код: {v1}\n\nВведите его на следующем экране и задайте новый пароль.',
        {'v0': _email.text.trim(), 'v1': code},
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
                icon: Icon(
                  Icons.chevron_left,
                  color: context.pal.accent,
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
                      child: Icon(
                        Icons.vpn_key_outlined,
                        size: 36,
                        color: context.pal.accent,
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
                        'Введите email, указанный при регистрации, и мы отправим код для восстановления доступа.',
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
                    const SizedBox(height: 14),
                    CustomButton(
                      label: tr('Отправить код'),
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
