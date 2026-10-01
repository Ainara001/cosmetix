import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/core/utils/validators.dart';
import 'package:cosmetix/providers/auth_provider.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/routes/route_args.dart';
import 'package:cosmetix/widgets/common_widgets.dart';
import 'package:cosmetix/widgets/custom_button.dart';
import 'package:cosmetix/widgets/custom_text_field.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _agree = false;
  bool _agreeError = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    FocusScope.of(context).unfocus();
    final valid = _formKey.currentState!.validate();
    setState(() {
      _agreeError = !_agree;
      _error = null;
    });
    if (!valid || !_agree) {
      if (valid && !_agree) {
        showMessage(
          context,
          'Примите условия использования',
          type: MessageType.warning,
        );
      }
      return;
    }
    setState(() => _loading = true);
    final error = await context.read<AuthProvider>().register(
      _name.text,
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
    showMessage(
      context,
      'Аккаунт создан. Добро пожаловать в Cosmetix!',
      type: MessageType.success,
    );
    Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.main, (_) => false);
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
    Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.main, (_) => false);
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
                      'Регистрация',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Создайте бьюти-профиль, чтобы подбирать идеальную косметику.',
                      style: AppTextStyles.body.copyWith(color: pal.subtext),
                    ),
                    const SizedBox(height: 20),
                    Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CustomTextField(
                            label: 'Имя',
                            hint: 'Введите ваше имя',
                            controller: _name,
                            validator: (v) => Validators.name(v),
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 14),
                          CustomTextField(
                            label: 'Email',
                            hint: 'example@mail.com',
                            controller: _email,
                            validator: Validators.email,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 14),
                          CustomTextField(
                            label: 'Пароль',
                            hint: 'Минимум 8 символов, буквы и цифры',
                            controller: _password,
                            isPassword: true,
                            validator: Validators.password,
                            onSubmitted: (_) => _register(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Checkbox(
                          value: _agree,
                          onChanged: (v) => setState(() {
                            _agree = v ?? false;
                            _agreeError = false;
                          }),
                        ),
                        Expanded(
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              const Text(
                                'Я согласен с ',
                                style: TextStyle(fontSize: 13),
                              ),
                              LinkText(
                                'условиями использования',
                                bold: false,
                                onTap: () => Navigator.pushNamed(
                                  context,
                                  AppRoutes.legal,
                                  arguments: LegalArgs.terms,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_agreeError)
                      const Padding(
                        padding: EdgeInsets.only(left: 12, bottom: 6),
                        child: Text(
                          'Необходимо принять условия',
                          style: TextStyle(
                            color: AppColors.danger,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    if (_error != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.saleSoft,
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
                    CustomButton(
                      label: 'Зарегистрироваться',
                      loading: _loading,
                      onPressed: _register,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Уже есть аккаунт?',
                          style: AppTextStyles.small.copyWith(
                            color: pal.subtext,
                          ),
                        ),
                        LinkText(
                          'Войти',
                          onTap: () => Navigator.of(context).maybePop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: Text(
                        'ИЛИ ЗАРЕГИСТРИРУЙТЕСЬ ЧЕРЕЗ',
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
