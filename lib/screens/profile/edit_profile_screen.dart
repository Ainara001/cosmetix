import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/core/utils/validators.dart';
import 'package:cosmetix/providers/auth_provider.dart';
import 'package:cosmetix/widgets/avatar_sheet.dart';
import 'package:cosmetix/widgets/common_widgets.dart';
import 'package:cosmetix/widgets/custom_button.dart';
import 'package:cosmetix/widgets/custom_text_field.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _first;
  late final TextEditingController _last;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _city;
  late int _avatar;
  bool _saving = false;

  static const _avatarColors = [
    0xFFD4A0AC,
    0xFFC88A9B,
    0xFFE88C90,
    0xFFB9A3D6,
    0xFF8FB8C9,
    0xFF9CC5A1,
  ];

  @override
  void initState() {
    super.initState();
    final u = context.read<AuthProvider>().user!;
    _first = TextEditingController(text: u.firstName);
    _last = TextEditingController(text: u.lastName);
    _email = TextEditingController(text: u.email);
    _phone = TextEditingController(text: u.phone);
    _city = TextEditingController(text: u.city);
    _avatar = u.avatarColor;
  }

  @override
  void dispose() {
    for (final c in [_first, _last, _email, _phone, _city]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr('Цвет аватара'),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final c in _avatarColors)
                  InkWell(
                    onTap: () => Navigator.pop(ctx, c),
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: c == _avatar
                              ? context.pal.accent
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: const Icon(
                        Icons.person_outline,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _avatar = picked);
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      showMessage(context, tr('Проверьте поля формы'), type: MessageType.error);
      return;
    }
    setState(() => _saving = true);
    final error = await context.read<AuthProvider>().updateProfile(
      firstName: _first.text,
      lastName: _last.text,
      email: _email.text,
      phone: _phone.text,
      city: _city.text,
      avatarColor: _avatar,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      showMessage(context, error, type: MessageType.error);
      return;
    }
    showMessage(context, tr('Изменения сохранены'), type: MessageType.success);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: tr('Профиль'),
      bigTitle: true,
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Center(
              child: Column(
                children: [
                  GestureDetector(
                    onTap: () =>
                        showAvatarSheet(context, onPickColor: _pickAvatar),
                    child: UserAvatar(
                      size: 76,
                      color: _avatar,
                      photoPath: context.watch<AuthProvider>().user?.avatarPath,
                    ),
                  ),
                  LinkText(
                    tr('Изменить фото'),
                    bold: false,
                    onTap: () =>
                        showAvatarSheet(context, onPickColor: _pickAvatar),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            CustomTextField(
              label: tr('Имя'),
              controller: _first,
              validator: (v) => Validators.name(v),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            CustomTextField(
              label: tr('Фамилия'),
              controller: _last,
              validator: (v) {
                if ((v ?? '').trim().isEmpty) return null;
                return Validators.name(v, tr('Фамилия'));
              },
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            CustomTextField(
              label: 'Email',
              controller: _email,
              validator: Validators.email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            CustomTextField(
              label: tr('Телефон'),
              hint: '+7 707 123 45 67',
              controller: _phone,
              validator: Validators.phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            CustomTextField(
              label: tr('Город'),
              controller: _city,
              validator: (v) =>
                  (v ?? '').length > 40 ? tr('Слишком длинное название') : null,
            ),
            const SizedBox(height: 22),
            CustomButton(
              label: tr('Сохранить изменения'),
              loading: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}
