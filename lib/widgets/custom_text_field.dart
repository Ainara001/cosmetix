import 'package:flutter/material.dart';

import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/theme/app_colors.dart';

/// Text field with a small uppercase label above it (as in Figma).
class CustomTextField extends StatefulWidget {
  const CustomTextField({
    super.key,
    this.label,
    this.hint,
    this.controller,
    this.validator,
    this.isPassword = false,
    this.keyboardType,
    this.textInputAction,
    this.maxLines = 1,
    this.maxLength,
    this.prefixIcon,
    this.suffixIcon,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.autofillHints,
    this.autovalidateMode,
  });

  final String? label;
  final String? hint;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final bool isPassword;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int maxLines;
  final int? maxLength;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final Iterable<String>? autofillHints;
  final AutovalidateMode? autovalidateMode;

  @override
  State<CustomTextField> createState() => _CustomTextFieldState();
}

class _CustomTextFieldState extends State<CustomTextField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!.toUpperCase(),
            style: AppTextStyles.label.copyWith(color: pal.subtext),
          ),
          const SizedBox(height: 6),
        ],
        TextFormField(
          controller: widget.controller,
          validator: widget.validator,
          obscureText: widget.isPassword && _hidden,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          maxLines: widget.isPassword ? 1 : widget.maxLines,
          maxLength: widget.maxLength,
          enabled: widget.enabled,
          onChanged: widget.onChanged,
          onFieldSubmitted: widget.onSubmitted,
          autofillHints: widget.autofillHints,
          autovalidateMode: widget.autovalidateMode,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: widget.hint,
            counterText: '',
            prefixIcon: widget.prefixIcon == null
                ? null
                : Icon(widget.prefixIcon, color: pal.subtext, size: 20),
            suffixIcon: widget.isPassword
                ? IconButton(
                    tooltip: _hidden ? 'Показать пароль' : 'Скрыть пароль',
                    icon: Icon(
                      _hidden
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: AppColors.primaryDark,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _hidden = !_hidden),
                  )
                : widget.suffixIcon,
          ),
        ),
      ],
    );
  }
}
