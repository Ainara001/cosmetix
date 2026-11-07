import 'dart:convert';

import 'package:cosmetix/core/beauty/beauty_codes.dart';
import 'package:cosmetix/services/ai/ai_client.dart';

/// Pulls the JSON object out of a model answer (models like to wrap JSON in
/// ```json fences or add a sentence around it).
Map<String, Object?> extractJsonObject(String raw) {
  var text = raw.trim();
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start < 0 || end <= start) {
    throw const AiBadResponse('No JSON object in the answer');
  }
  text = text.substring(start, end + 1);
  try {
    final v = jsonDecode(text);
    if (v is Map<String, Object?>) return v;
  } catch (_) {}
  throw const AiBadResponse('Invalid JSON in the answer');
}

double _confidence(Object? v) {
  if (v is num && v.isFinite) return v.toDouble().clamp(0.0, 1.0);
  return 0;
}

String _text(Object? v, int max) {
  if (v is! String) return '';
  final t = v.trim();
  return t.length > max ? t.substring(0, max) : t;
}

String _norm(Object? v) => v is String
    ? v.trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_')
    : '';

/// Result of the optional photo analysis (a hint, never a diagnosis).
///
/// Only the three codes (and the model's own self-report, see
/// `BeautyProfileMerger.minConfidence`) are kept. Free text the model may add
/// ("observations", "explanation") is dropped on purpose: nothing measured the
/// statements it makes about the skin, so they are never carried or shown.
class VisionAnalysis {
  const VisionAnalysis({
    this.skinTone,
    this.undertone,
    this.colorType,
    required this.confidence,
  });

  final SkinTone? skinTone;
  final Undertone? undertone;
  final ColorType? colorType;

  /// 0..1
  final double confidence;

  /// Parses and validates the model answer. Unsupported values become null;
  /// throws [AiBadResponse] when nothing usable is left.
  factory VisionAnalysis.parse(String raw) {
    final j = extractJsonObject(raw);
    final tone = _norm(j['skinTone']);
    final skinTone = switch (tone) {
      'very_light' || 'fair' || 'porcelain' => SkinTone.veryLight,
      'light' => SkinTone.light,
      'medium' || 'olive' => SkinTone.medium,
      'tan' || 'dark' => SkinTone.tan,
      'deep' || 'very_dark' => SkinTone.deep,
      _ => null,
    };
    final undertone = Undertone.fromCode(_norm(j['undertone']));
    final colorType = ColorType.fromCode(_norm(j['colorType']));
    if (skinTone == null && undertone == null && colorType == null) {
      throw const AiBadResponse('The analysis has no supported values');
    }
    return VisionAnalysis(
      skinTone: skinTone,
      undertone: undertone,
      colorType: colorType,
      confidence: _confidence(j['confidence']),
    );
  }
}

/// AI opinion about who a product suits. Only used as extra input; stored in
/// SQLite with source 'ai'.
class ProductClassification {
  const ProductClassification({
    this.colorTypes = const {},
    this.undertones = const {},
    this.skinTypes = const {},
    this.concerns = const {},
    required this.confidence,
    this.explanation = '',
  });

  final Set<ColorType> colorTypes;
  final Set<Undertone> undertones;
  final Set<SkinType> skinTypes;
  final Set<SkinConcern> concerns;
  final double confidence;
  final String explanation;

  bool get isEmpty =>
      colorTypes.isEmpty &&
      undertones.isEmpty &&
      skinTypes.isEmpty &&
      concerns.isEmpty;

  factory ProductClassification.parse(String raw) {
    final j = extractJsonObject(raw);
    Set<T> codes<T>(Object? v, T? Function(String) parse) => {
      if (v is List)
        for (final e in v)
          if (e is String && parse(_norm(e)) != null) parse(_norm(e)) as T,
    };
    return ProductClassification(
      colorTypes: codes(j['colorTypes'], ColorType.fromCode),
      undertones: codes(j['undertones'], Undertone.fromCode),
      skinTypes: codes(j['skinTypes'], SkinType.fromCode),
      concerns: codes(j['concerns'], SkinConcern.fromCode),
      confidence: _confidence(j['confidence']),
      explanation: _text(j['explanation'], 300),
    );
  }
}
