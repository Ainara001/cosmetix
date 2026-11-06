import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
  "colorType": "spring" | "summer" | "autumn" | "winter"
}
Write nothing else: no text, no description of the skin. Do not describe or comment on skin condition, texture, redness, spots, pigmentation or any disease. Do not guess the person's age, ethnicity or identity.''';

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
          prompt, // no text is requested, so there is no language to ask for
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
