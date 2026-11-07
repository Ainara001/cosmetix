import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/services/photo_check/photo_rules.dart';

/// The text for one reason the photo check gave. The user sees only this,
/// never a number.
String photoIssueText(PhotoIssue i) => switch (i) {
  PhotoIssue.unreadable => tr(
    'Не удалось открыть фото. Файл повреждён или это не картинка.',
  ),
  PhotoIssue.checkFailed => tr('Не удалось проверить фото. Попробуйте другое.'),
  PhotoIssue.noFace => tr(
    'На фото не нашли лицо. Снимите лицо анфас, крупным планом.',
  ),
  PhotoIssue.severalFaces => tr(
    'На фото несколько лиц. Нужно фото одного человека.',
  ),
  PhotoIssue.backgroundFace => tr(
    'В кадре есть ещё одно, меньшее лицо. Лучше фото одного человека.',
  ),
  PhotoIssue.faceSmall => tr(
    'Лицо слишком маленькое или далеко. Снимите ближе.',
  ),
  PhotoIssue.blurry => tr(
    'Фото нечёткое. Снимите без движения и при хорошем свете.',
  ),
  PhotoIssue.tooDark => tr('Слишком темно. Встаньте к окну или включите свет.'),
  PhotoIssue.overexposed => tr(
    'Лицо пересвечено. Уйдите от прямого света или вспышки.',
  ),
  PhotoIssue.grayscale => tr(
    'Чёрно-белое фото не подходит для определения цвета кожи.',
  ),
  PhotoIssue.turned => tr('Лицо повёрнуто. Смотрите прямо в камеру.'),
  PhotoIssue.eyesCovered => tr('Глаза закрыты тёмными очками. Снимите очки.'),
  PhotoIssue.littleSkin => tr(
    'Заметная часть лица закрыта волосами, бородой, маской или тенью.',
  ),
  PhotoIssue.unevenLight => tr(
    'Свет падает с одной стороны. Результат может быть неточным.',
  ),
};
