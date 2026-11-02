import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/models/ai_models.dart';
import 'package:cosmetix/services/ai/ai_client.dart';

/// Optional photo step of the Beauty Test: sends one small photo to the
/// AI (through the proxy) and expects structured JSON back. The caller
/// must have the user's consent first (see `AiProvider.sharePhotos`).
class VisionAnalyzer {
  VisionAnalyzer(this._client);

  final AiClient _client;

  /// Photos bigger than this are rejected before sending (the picker already
  /// downsizes to ~1024px, so real photos are a few hundred KB).
  static const maxBytes = 4 * 1024 * 1024;

  static const prompt = '''
You analyze a selfie ONLY to help choose cosmetics. This is not a medical assessment.
Estimate from the photo: the person's skin tone, skin undertone and the most likely seasonal color type.
Answer with ONE JSON object and nothing else, using exactly these keys:
{
  "skinTone": "very_light" | "light" | "medium" | "tan" | "deep",
  "undertone": "warm" | "cool" | "neutral",
  "colorType": "spring" | "summer" | "autumn" | "winter",
  "observations": [short strings about visible cosmetic characteristics, max 4],
  "confidence": number from 0 to 1 (use a low value for dark, blurry or filtered photos),
  "explanation": "one or two sentences"
}
Do not describe diseases or skin conditions. Do not guess the person's age, ethnicity or identity.
Write "observations" and "explanation" in the requested language (the JSON keys and values of skinTone, undertone and colorType stay exactly as listed above).''';

  /// [photoBytes] is a resized JPEG. Throws [AiException] subclasses.
  Future<VisionAnalysis> analyze(Uint8List photoBytes) async {
    if (photoBytes.isEmpty || photoBytes.length > maxBytes) {
      throw const AiBadResponse('The photo is empty or too large');
    }
    final reply = await _client.chat(
      json: true,
      temperature: 0.2,
      timeout: AiClient.visionTimeout,
      messages: [
        AiMessage(
          'user',
          '$prompt\nRequested language: ${currentLang.englishName}.',
          images: [base64Encode(photoBytes)], // never logged
        ),
      ],
    );
    return VisionAnalysis.parse(reply.text);
  }

  /// Reads the picked photo, analyzes it and always deletes the temporary file
  /// afterwards (the Beauty photo is not stored).
  Future<VisionAnalysis> analyzeFile(File photo) async {
    try {
      return await analyze(await photo.readAsBytes());
    } finally {
      try {
        if (await photo.exists()) await photo.delete();
      } catch (_) {}
    }
  }
}
