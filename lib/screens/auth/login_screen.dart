import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/core/utils/validators.dart';
import 'package:cosmetix/database/seed_data.dart';
import 'package:cosmetix/providers/auth_provider.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/common_widgets.dart';
import 'package:cosmetix/widgets/custom_button.dart';
import 'package:cosmetix/widgets/custom_text_field.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _goHome() => Navigator.of(
    context,
  ).pushNamedAndRemoveUntil(AppRoutes.main, (_) => false);

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      setState(() => _error = null);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final error = await context.read<AuthProvider>().login(
      _email.text,
      _password.text,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _loading = false;
        _error = error;
      });
      return;
    }
    _goHome();
  }

  Future<void> _social(String provider) async {
    setState(() => _loading = true);
    final error = await context.read<AuthProvider>().socialLogin(provider);
    if (!mounted) return;
    if (error != null) {
      setState(() => _loading = false);
      showMessage(context, error, type: MessageType.error);
      return;
    }
    showMessage(
      context,
      trf('Вход через {provider} выполнен (локальный аккаунт)', {
        'provider': provider,
      }),
      type: MessageType.success,
    );
    _goHome();
  }

  void _fillDemo() {
    _email.text = SeedData.demoEmail;
    _password.text = SeedData.demoPassword;
    setState(() => _error = null);
    showMessage(
      context,
      tr('Подставлены данные демо-аккаунта'),
      type: MessageType.info,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Cosmetix', style: AppTextStyles.subtitle),
                  ),
                  Tooltip(
                    message: tr('Заполнить демо-аккаунт'),
                    child: InkWell(
                      onTap: _fillDemo,
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: pal.border),
                        ),
                        child: Icon(
                          Icons.auto_awesome,
                          size: 18,
                          color: context.pal.accent,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Text(tr('Добро пожаловать'), style: AppTextStyles.h1),
              const SizedBox(height: 10),
              Text(
                tr(
                  'Войдите в свой бьюти-профиль, чтобы открывать персональные рекомендации и продолжать покупки.',
                ),
                style: AppTextStyles.body.copyWith(color: pal.subtext),
              ),
              const SizedBox(height: 22),
              AppCard(
                radius: 20,
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      CustomTextField(
                        label: 'Email',
                        hint: 'example@mail.com',
                        controller: _email,
                        validator: Validators.email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                      ),
                      const SizedBox(height: 14),
                      CustomTextField(
                        label: tr('Пароль'),
                        hint: '••••••••',
                        controller: _password,
                        isPassword: true,
                        validator: Validators.loginPassword,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _login(),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: LinkText(
                          tr('Забыли пароль?'),
                          bold: false,
                          onTap: () => Navigator.pushNamed(
                            context,
                            AppRoutes.forgotPassword,
                          ),
                        ),
                      ),
                      if (_error != null) ...[
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: context.pal.redSoft,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: AppColors.sale,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                      CustomButton(
                        label: tr('Войти'),
                        loading: _loading,
                        onPressed: _login,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Center(
                child: Text(
                  tr('ИЛИ ВОЙТИ ЧЕРЕЗ'),
                  style: AppTextStyles.label.copyWith(color: pal.subtext),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SocialButton(
                      label: 'Google',
                      icon: Icons.g_mobiledata_rounded,
                      onTap: () => _social('Google'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SocialButton(
                      label: 'Apple',
                      icon: Icons.apple,
                      onTap: () => _social('Apple'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    tr('Нет аккаунта?'),
                    style: AppTextStyles.small.copyWith(color: pal.subtext),
                  ),
                  LinkText(
                    tr('Регистрация'),
                    onTap: () =>
                        Navigator.pushNamed(context, AppRoutes.register),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
