class AppConstants {
  AppConstants._();

  static const appName = 'Cosmetix';
  static const version = '2.4.1 (Build 412)';

  /// Main product categories (Search screen, filters, home icons).
  static const categories = [
    'Макияж',
    'Уход за лицом',
    'Парфюмерия',
    'Тело и ванна',
    'Волосы',
    'Подарки',
  ];

  /// Zone chips on the catalog screen.
  static const zones = ['Лицо', 'Глаза', 'Губы', 'Тело'];

  static const skinTypes = [
    'Сухая',
    'Нормальная',
    'Жирная',
    'Комбинированная',
    'Чувствительная',
  ];
  static const skinTones = [
    'Очень светлый',
    'Светлый',
    'Средний',
    'Смуглый',
    'Тёмный',
  ];
  static const undertones = ['Холодный', 'Тёплый', 'Нейтральный'];
  static const colorTypes = ['Весна', 'Лето', 'Осень', 'Зима'];
  static const skinConcerns = [
    'Сухость и шелушение',
    'Пигментация',
    'Акне и высыпания',
    'Чувствительность и покраснения',
    'Морщины и возраст',
  ];

  static const reactionTypes = [
    'Покраснение и зуд',
    'Сильные высыпания',
    'Лёгкое шелушение',
    'Отёк',
    'Жжение',
    'Другое',
  ];

  static const maxPrice = 50000;
}
