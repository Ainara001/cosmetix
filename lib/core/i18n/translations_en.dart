import 'package:cosmetix/core/constants/legal_texts.dart';

// Russian source text -> translation (edit here; the old helper scripts are in tool/i18n_legacy).
const Map<String, String> translationsEn = {
  LegalTexts.privacy: '''1. What data we store
Cosmetix stores data only on your device in a local SQLite database: name, email, contact details, beauty profile, favorites, orders, reviews and reaction diary entries.

2. What the data is used for
The data is needed to pick cosmetics for your skin type and color type, warn about unwanted ingredients and show your purchase history.

3. Sharing with third parties
The app does not send your data to a server and does not share it with third parties.

4. Managing data
You can edit your profile data, delete diary entries, clear your search history and fully reset the app data in the Settings section.

5. Password
The password is stored as a hash and is never shown in plain text.''',
  LegalTexts.terms: '''1. General provisions
Cosmetix is a study app for comparing cosmetics prices, analyzing ingredients and choosing skincare. By using the app, you agree to these terms.

2. Informational nature
Recommendations on ingredients and color type are for reference only and do not replace a consultation with a dermatologist or cosmetologist.

3. Prices and availability
Prices and product availability in stores are demonstration data and may differ from real ones.

4. Orders
Placing an order in the app is a local simulation: no payment is made and no goods are delivered.

5. User responsibility
You are responsible for the accuracy of the data you provide and for keeping your password safe.''',
  ' Внимание: в составе есть компоненты из вашего чёрного списка — {v0}.':
      ' Warning: the ingredients include components from your blacklist — {v0}.',
  '+{v0} бонусов': '+{v0} bonus points',
  'BHA-кислота. Очищает поры. Возможна сухость.':
      'BHA acid. Cleanses pores. May cause dryness.',
  'Email слишком длинный (максимум 254)': 'Email is too long (maximum 254)',
  '{distanceM} м от вас': '{distanceM} m from you',
  '{field} может содержать только буквы': '{field} may contain letters only',
  '{field} обязательно для заполнения': '{field} is required',
  '{field} слишком длинное (максимум 40)': '{field} is too long (maximum 40)',
  '{field} слишком длинное (максимум {max})':
      '{field} is too long (maximum {max})',
  '{field} слишком короткое (минимум 2 буквы)':
      '{field} is too short (minimum 2 letters)',
  '{field} слишком короткое (минимум {min} символов)':
      '{field} is too short (minimum {min} characters)',
  '{n} {unit} назад': '{n} {unit} ago',
  '{n} мин назад': '{n} min ago',
  '{v0} км': '{v0} km',
  '{v0} км от вас': '{v0} km from you',
  '{v0} м': '{v0} m',
  '{v0} от вас': '{v0} from you',
  '{v0} стоит {v1}, а {v2} — {v3}. Если бюджет важнее, то «{v4}» выигрывает по цене.':
      '{v0} costs {v1}, and {v2} — {v3}. If budget matters more, "{v4}" wins on price.',
  '{v0} фото': '{v0} photos',
  '{v0}% натуральных и немедикаментозных компонентов.':
      '{v0}% natural and non-medicinal ingredients.',
  '«{v0}» ({v1}) — {v2}. {v3} Спросите про состав или сравнение цен.':
      '"{v0}" ({v1}) — {v2}. {v3} Ask about the ingredients or a price comparison.',
  '«{v0}» будет удалён из корзины.': '"{v0}" will be removed from the cart.',
  '«{v0}» добавлен в корзину': '"{v0}" added to cart',
  '«{v0}» от {v1} в магазине {v2} ({v3}).': '"{v0}" from {v1} at {v2} ({v3}).',
  '«{v0}» стоит {v1}.': '"{v0}" costs {v1}.',
  '«{v0}» удалён из избранного': '"{v0}" removed from favorites',
  '«{v0}»: оценка состава {v1}/10 ({v2}). {v3}':
      '"{v0}": ingredient score {v1}/10 ({v2}). {v3}',
  '«От» больше «До»': '"From" is greater than "To"',
  'Августа': 'August',
  'Аккаунт с таким email не найден': 'No account found with this email',
  'Аккаунт создан. Добро пожаловать в Cosmetix!':
      'Account created. Welcome to Cosmetix!',
  'Акне и высыпания': 'Acne and breakouts',
  'Анализ состава': 'Ingredient analysis',
  'Антибактериальное вещество': 'Antibacterial agent',
  'Антибактериальное вещество.': 'Antibacterial agent.',
  'Апреля': 'April',
  'Ароматизатор. Может вызвать раздражение.':
      'Fragrance. May cause irritation.',
  'Астана': 'Astana',
  'БОНУСЫ': 'BONUSES',
  'Базовый увлажняющий крем на каждый день.':
      'A basic everyday moisturizing cream.',
  'Безопасный состав': 'Safe formula',
  'Беру уже вторую, всем советую.':
      'Buying my second one, I recommend it to everyone.',
  'Блеск Rom&nd Glasting': 'Rom&nd Glasting Gloss',
  'Ближе ко мне': 'Closest to me',
  'Большинство ингредиентов безопасны. Обнаружен {criticalCount} {word}.':
      'Most ingredients are safe. Found {criticalCount} {word}.',
  'Будет найдено примерно {_found} товаров':
      'About {_found} products will be found',
  'Бьюти-профиль': 'Beauty profile',
  'В НАЛИЧИИ': 'IN STOCK',
  'В избранное': 'Add to favorites',
  'В избранном пока пусто': 'Favorites are empty for now',
  'В корзине нет товаров по выбранным фильтрам':
      'No products in the cart match the selected filters',
  'В корзину': 'Add to cart',
  'В магазине «{v0}» товара нет в наличии': '"{v0}" is out of stock',
  'В магазине «{v0}» товара нет в наличии. Выберите другой магазин.':
      '"{v0}" is out of stock. Choose another store.',
  'В наличии': 'In stock',
  'В составе найдено: {v0}. Нажмите, чтобы изменить чёрный список.':
      'Found in the formula: {v0}. Tap to edit the blacklist.',
  'Валюта': 'Currency',
  'Вам нужно будет снова войти, чтобы увидеть свои данные.':
      'You will need to sign in again to see your data.',
  'Ваш цветотип: {v0}': 'Your color type: {v0}',
  'Ваши индивидуальные особенности кожи и цветотипа для более точного подбора косметики.':
      'Your individual skin and color-type traits for more accurate cosmetics selection.',
  'Ваши оттенки': 'Your shades',
  'Введите email': 'Enter your email',
  'Введите ваше имя': 'Enter your name',
  'Введите название компонента': 'Enter the ingredient name',
  'Введите номер в формате +7 707 123 45 67':
      'Enter a number in the format +7 707 123 45 67',
  'Введите пароль': 'Enter your password',
  'Введите сообщение': 'Enter a message',
  'Вернуться к входу': 'Back to sign in',
  'Версия приложения {v0}': 'App version {v0}',
  'Весна': 'Spring',
  'Весь каталог': 'Full catalog',
  'Витамин Е. Антиоксидант, защищает кожу.':
      'Vitamin E. Antioxidant, protects the skin.',
  'Вода / Aqua': 'Water / Aqua',
  'Возможно, он был удалён из каталога':
      'It may have been removed from the catalog',
  'Войдите в свой бьюти-профиль, чтобы открывать персональные рекомендации и продолжать покупки.':
      'Sign in to your beauty profile to get personal recommendations and keep shopping.',
  'Войти': 'Sign in',
  'Волосы': 'Hair',
  'Восстанавливающий шампунь для повреждённых волос.':
      'Repairing shampoo for damaged hair.',
  'Все': 'All',
  'Все ваши данные (аккаунты, заказы, избранное, отзывы) будут удалены, а база вернётся к исходным демо-данным.':
      'All your data (accounts, orders, favorites, reviews) will be deleted and the database will return to the initial demo data.',
  'Все категории': 'All categories',
  'Все отзывы': 'All reviews',
  'Все сообщения будут удалены.': 'All messages will be deleted.',
  'Все товары будут удалены из корзины.':
      'All items will be removed from the cart.',
  'Все цены': 'All prices',
  'Вспомнили пароль?': 'Remembered your password?',
  'Вход через {provider} выполнен (локальный аккаунт)':
      'Signed in with {provider} (local account)',
  'Вы не авторизованы': 'You are not signed in',
  'Выберите один из вариантов': 'Choose one of the options',
  'Выберите оценку': 'Choose a rating',
  'Выберите продукт': 'Choose a product',
  'Выберите реакцию': 'Choose a reaction',
  'Выберите тип реакции': 'Choose a reaction type',
  'Выберите цвет вен': 'Choose your vein color',
  'Выбрать из галереи': 'Choose from gallery',
  'Выйти': 'Sign out',
  'Выйти из аккаунта': 'Sign out of account',
  'Выйти из аккаунта?': 'Sign out of your account?',
  'Выравнивает тон и сужает поры.': 'Evens out skin tone and tightens pores.',
  'Гиалуроновая кислота / Hyaluronic Acid': 'Hyaluronic Acid',
  'Главная': 'Home',
  'Глаза': 'Eyes',
  'Глицерин / Glycerin': 'Glycerin',
  'Глубокий тёплый тип: вам подходят терракотовые, медные и тёплые коричневые оттенки.':
      'Deep warm type: terracotta, copper and warm brown shades suit you.',
  'Глубоко увлажняет кожу.': 'Deeply moisturizes the skin.',
  'Глянцевый блеск с эффектом стекла.': 'Glossy shine with a glass effect.',
  'Голубые / серые': 'Blue / gray',
  'Город': 'City',
  'Готово': 'Done',
  'Губы': 'Lips',
  'Далее': 'Next',
  'Дата': 'Date',
  'Дата реакции': 'Reaction date',
  'Действия': 'Actions',
  'Декабря': 'December',
  'Диапазон цены': 'Price range',
  'Диметикон / Dimethicone': 'Dimethicone',
  'Для этого товара пока нет цен в магазинах':
      'There are no store prices for this product yet',
  'Дневник Аллергии': 'Allergy diary',
  'Дневник реакций': 'Reaction diary',
  'До': 'To',
  'Добавить': 'Add',
  'Добавить в дневник': 'Add to diary',
  'Добавить в корзину из этого магазина': 'Add to cart from this store',
  'Добавить реакцию': 'Add reaction',
  'Добавить свой компонент...': 'Add your own ingredient...',
  'Добавить фото товара': 'Add a product photo',
  'Добавлено в избранное': 'Added to favorites',
  'Добавлено в корзину: {v0}': 'Added to cart: {v0}',
  'Добавьте компонент, которого хотите избегать':
      'Add an ingredient you want to avoid',
  'Добавьте товары из каталога, чтобы оформить заказ':
      'Add items from the catalog to place an order',
  'Добро пожаловать': 'Welcome',
  'Доллар (\$)': 'Dollar (\$)',
  'Доступна в {available} {v0}': 'Available in {available} {v0}',
  'Другое': 'Other',
  'Есть компоненты из чёрного списка': 'Contains blacklisted ingredients',
  'Есть скидки?': 'Any discounts?',
  'Ещё одну в корзину': 'One more to cart',
  'Жжение': 'Burning',
  'Жирная': 'Oily',
  'Забыли пароль?': 'Forgot your password?',
  'Завершить и показать результат': 'Finish and show the result',
  'Загораю легко': 'I tan easily',
  'Заказ удалён': 'Order deleted',
  'Заказ №{v0} оформлен': 'Order #{v0} placed',
  'Заказ №{v0} • {v1}': 'Order #{v0} • {v1}',
  'Заменить фото': 'Replace photo',
  'Заметка (необязательно)': 'Note (optional)',
  'Записывайте реакции кожи на косметику, чтобы избегать неподходящих средств':
      'Record your skin reactions to cosmetics to avoid unsuitable products',
  'Запись будет удалена из дневника реакций.':
      'The entry will be deleted from the reaction diary.',
  'Запись обновлена': 'Entry updated',
  'Запись удалена': 'Entry deleted',
  'Заполнить демо-аккаунт': 'Fill in demo account',
  'Зарегистрироваться': 'Sign up',
  'Здравствуйте! Спросите меня о ценах, составе, скидках или попросите подобрать косметику.':
      'Hello! Ask me about prices, ingredients, discounts, or ask me to pick cosmetics for you.',
  'Здравствуйте! Я ИИ-помощник Cosmetix. Какой вопрос по косметике или уходу за собой я могу помочь решить сегодня?':
      'Hello! I am the Cosmetix AI assistant. What question about cosmetics or self-care can I help you with today?',
  'Зелёные / Оливковые': 'Green / olive',
  'Зелёные / ореховые': 'Green / hazel',
  'Зима': 'Winter',
  'Золотое Яблоко': 'Golden Apple',
  'ИИ Чат': 'AI Chat',
  'ИИ-помощник': 'AI assistant',
  'ИЛИ ВОЙТИ ЧЕРЕЗ': 'OR SIGN IN WITH',
  'ИЛИ ЗАРЕГИСТРИРУЙТЕСЬ ЧЕРЕЗ': 'OR SIGN UP WITH',
  'ИНФОРМАЦИЯ': 'INFORMATION',
  'Из вашего чёрного списка: {v0}': 'From your blacklist: {v0}',
  'Избранное': 'Favorites',
  'Изменения сохранены': 'Changes saved',
  'Изменить фото': 'Change photo',
  'Имя': 'Name',
  'История кожных реакций': 'Skin reaction history',
  'История поиска': 'Search history',
  'Итого': 'Total',
  'Итого ({v0})': 'Total ({v0})',
  'Июля': 'July',
  'Июня': 'June',
  'К сожалению, подходящих товаров не нашлось.':
      'Unfortunately, no suitable products were found.',
  'К тесту на подтон': 'To the undertone test',
  'Кабинет': 'Account',
  'Как кожа реагирует на солнце?': 'How does your skin react to the sun?',
  'Какого цвета ваши глаза?': 'What color are your eyes?',
  'Какого цвета вены на вашем запястье?':
      'What color are the veins on your wrist?',
  'Какой состав у палетки Flower Knows?':
      'What is the composition of the Flower Knows palette?',
  'Какой у вас естественный оттенок губ и румянца?':
      'What is your natural lip and cheek color?',
  'Какой у вас естественный цвет кожи?': 'What is your natural skin color?',
  'Какой у вас натуральный цвет волос?': 'What is your natural hair color?',
  'Канцерогенный консервант': 'Carcinogenic preservative',
  'Канцерогенный консервант.': 'Carcinogenic preservative.',
  'Каталог': 'Catalog',
  'Каталог пуст': 'The catalog is empty',
  'Категория': 'Category',
  'Кожа': 'Skin',
  'Кожа стала заметно ровнее за две недели.':
      'My skin became noticeably smoother in two weeks.',
  'Комбинированная': 'Combination',
  'Компонент «{text}» добавлен в чёрный список':
      'Ingredient "{text}" added to the blacklist',
  'Компонент «{v0}» будет удалён из чёрного списка.':
      'Ingredient "{v0}" will be removed from the blacklist.',
  'Консервант. Потенциальный аллерген.': 'Preservative. Potential allergen.',
  'Контрастный холодный тип: яркие ягодные, винные и чистые холодные оттенки подчеркнут вашу внешность.':
      'High-contrast cool type: bright berry, wine and pure cool shades will highlight your features.',
  'Коралловый': 'Coral',
  'Корзина': 'Cart',
  'Корзина очищена': 'Cart cleared',
  'Корзина пуста': 'Cart is empty',
  'Корзина уже пуста': 'The cart is already empty',
  'Красивая упаковка, цвета как на фото.':
      'Beautiful packaging, colors as in the photo.',
  'Краснею, потом загораю': 'I burn first, then tan',
  'Крем SPF 50 Relief Sun': 'SPF 50 Relief Sun Cream',
  'Критических компонентов не обнаружено.': 'No critical ingredients found.',
  'Культовый тинт для губ, держится до 8 часов.':
      'Iconic lip tint that lasts up to 8 hours.',
  'Кушон Missha Magic': 'Missha Magic Cushion',
  'Лаурилсульфат натрия / SLS': 'Sodium Lauryl Sulfate / SLS',
  'Легкое шелушение': 'Light peeling',
  'Лето': 'Summer',
  'Лицо': 'Face',
  'Лучшая цена: от {v0}': 'Best price: from {v0}',
  'Лучший SPF, что я пробовала, не оставляет белых следов.':
      'The best SPF I have tried, leaves no white cast.',
  'Любой статус': 'Any status',
  'Лёгкая сыворотка с ниацинамидом и гиалуроновой кислотой.':
      'Light serum with niacinamide and hyaluronic acid.',
  'Лёгкий кушон с сияющим финишем и SPF.':
      'Light cushion with a glowing finish and SPF.',
  'Лёгкое шелушение': 'Light peeling',
  'Макияж': 'Makeup',
  'Максимум 10 штук одного товара': 'Maximum 10 pieces of one product',
  'Максимум 300 символов': 'Maximum 300 characters',
  'Матирующий наполнитель.': 'Mattifying filler.',
  'Мая': 'May',
  'Минеральное масло': 'Mineral oil',
  'Минеральное масло / Mineral Oil': 'Mineral Oil',
  'Минеральный УФ-фильтр.': 'Mineral UV filter.',
  'Минимум 8 символов, буквы и цифры':
      'At least 8 characters, letters and digits',
  'Мои покупки': 'My purchases',
  'Морщины и возраст': 'Wrinkles and aging',
  'Мы пришлём вам уведомление, когда цены на избранные товары снизятся.':
      'We will notify you when prices of your favorite products drop.',
  'Мягкие тени, легко растушевываются.': 'Soft shadows, blend easily.',
  'НЕТ В НАЛИЧИИ': 'OUT OF STOCK',
  'На главную': 'To home',
  'Набор уходовой косметики в подарочной упаковке.':
      'A skincare set in gift packaging.',
  'Нажмите на сердечко у товара, чтобы сохранить его здесь':
      'Tap the heart on a product to save it here',
  'Назад': 'Back',
  'Название слишком короткое': 'The name is too short',
  'Наименование': 'Name',
  'Настройки': 'Settings',
  'Натуральный воск, смягчает губы.': 'Natural wax, softens the lips.',
  'Начислено бонусов': 'Bonuses earned',
  'Не больше {max}': 'No more than {max}',
  'Не может быть отрицательным': 'Cannot be negative',
  'Не удалось войти через {provider}': 'Could not sign in with {provider}',
  'Не удалось выполнить вход. Попробуйте ещё раз':
      'Could not sign in. Please try again',
  'Не удалось добавить товар в корзину':
      'Could not add the product to the cart',
  'Не удалось загрузить каталог': 'Could not load the catalog',
  'Не удалось загрузить состав этого товара':
      'Could not load the ingredients of this product',
  'Не удалось изменить пароль': 'Could not change the password',
  'Не удалось открыть этот экран. Вернитесь назад.':
      'Could not open this screen. Go back.',
  'Не удалось оформить заказ. Попробуйте ещё раз':
      'Could not place the order. Please try again',
  'Не удалось получить фото. Проверьте доступ к камере/галерее.':
      'Could not get the photo. Check camera/gallery access.',
  'Не удалось сбросить данные': 'Could not reset the data',
  'Не удалось создать аккаунт. Попробуйте ещё раз':
      'Could not create the account. Please try again',
  'Не удалось сохранить запись': 'Could not save the entry',
  'Не удалось сохранить изменения': 'Could not save the changes',
  'Не удалось сохранить отзыв': 'Could not save the review',
  'Не удалось сохранить результат': 'Could not save the result',
  'Неверный email или пароль': 'Wrong email or password',
  'Нежный цветочно-мускусный аромат на весь день.':
      'A gentle floral-musk fragrance for the whole day.',
  'Нейтральный': 'Neutral',
  'Некорректный email, например name@mail.com':
      'Invalid email, for example name@mail.com',
  'Необходимо принять условия': 'You must accept the terms',
  'Нет': 'No',
  'Нет аккаунта?': 'No account?',
  'Нет в наличии': 'Out of stock',
  'Нет предложений': 'No offers',
  'Ниацинамид / Niacinamide': 'Niacinamide',
  'Нифига себе рил качественно - держится долго, не чувствуется на коже и не подчеркивает поры.':
      'Seriously good quality - lasts long, can\'t be felt on the skin and doesn\'t emphasize pores.',
  'Нифига себе рил качественно - отлично подходит для ежедневного макияжа и не вызывает дискомфорта.':
      'Seriously good quality - perfect for everyday makeup and causes no discomfort.',
  'Нифига себе рил качественно - оттенок понравился, но на второй день слегка блестит.':
      'Seriously good quality - liked the shade, but it gets slightly shiny on the second day.',
  'Ничего не найдено': 'Nothing found',
  'Новый пароль': 'New password',
  'Нормальная': 'Normal',
  'Ноября': 'November',
  'Нужна помощь с выбором - что меньше стоит: палетка FlowerKnows или Peripera?':
      'I need help choosing - which costs less: the FlowerKnows or the Peripera palette?',
  'О товаре': 'About the product',
  'Оксид цинка / Zinc Oxide': 'Zinc Oxide',
  'Октября': 'October',
  'Оливковая / средняя': 'Olive / medium',
  'Описание': 'Description',
  'Опишите реакцию': 'Describe the reaction',
  'Осень': 'Autumn',
  'Основной растворитель, абсолютно безопасен.':
      'The main solvent, completely safe.',
  'Оставьте первый отзыв об этом товаре':
      'Leave the first review of this product',
  'Оставьте свой отзыв': 'Leave your review',
  'От': 'From',
  'Отзыв': 'Review',
  'Отзыв обновлён': 'Review updated',
  'Отзыв удалён': 'Review deleted',
  'Отзывов пока нет': 'No reviews yet',
  'Отзывов пока нет. Станьте первым!': 'No reviews yet. Be the first!',
  'Отзывы': 'Reviews',
  'Отзывы{v0}': 'Reviews{v0}',
  'Отличный состав!': 'Great ingredients!',
  'Отмена': 'Cancel',
  'Отменить': 'Undo',
  'Отметьте компоненты, которых не должно быть в вашей косметике. Мы предупредим вас при анализе продукта и не будем показывать такие товары в персональных рекомендациях.':
      'Mark the ingredients that should not be in your cosmetics. We will warn you when analyzing a product and will not show such products in your personal recommendations.',
  'Отправить': 'Send',
  'Отправить отзыв': 'Submit review',
  'Отёк': 'Swelling',
  'Оформить': 'Check out',
  'Оформить заказ': 'Place order',
  'Оформить заказ?': 'Place the order?',
  'Оформлен': 'Placed',
  'Оформленные заказы появятся здесь': 'Placed orders will appear here',
  'Оцените товар': 'Rate the product',
  'Очень нежные оттенки, пигмент хороший.':
      'Very delicate shades, good pigment.',
  'Очень светлая, фарфоровая': 'Very fair, porcelain',
  'Очень светлый': 'Very light',
  'Очистить': 'Clear',
  'Очистить корзину': 'Clear cart',
  'Очистить корзину?': 'Clear the cart?',
  'Очистить переписку?': 'Clear the conversation?',
  'Очистить чат': 'Clear chat',
  'Ошибка': 'Error',
  'ПОДТОН': 'UNDERTONE',
  'ПОСЕЩЕНИЯ': 'VISITS',
  'ПРЕДПОЧТЕНИЯ': 'PREFERENCES',
  'Палетка Flower Knows Strawberry': 'Flower Knows Strawberry Palette',
  'Палетка Flower Knows стоит 2 500 тг, а Peripera Ink Cozy - 4 800 тг. Если бюджет важнее, то Flower Knows сейчас выигрывает по цене.':
      'The Flower Knows palette costs 2 500 KZT, and the Peripera Ink Cozy - 4 800 KZT. If budget matters more, Flower Knows wins on price right now.',
  'Палетка Peripera Ink Cozy': 'Peripera Ink Cozy Palette',
  'Палетка из 9 нежных оттенков с мерцающими и матовыми текстурами.':
      'A palette of 9 delicate shades with shimmer and matte textures.',
  'Парабены': 'Parabens',
  'Парабены / Parabens': 'Parabens',
  'Пароли не совпадают': 'Passwords do not match',
  'Пароль': 'Password',
  'Пароль должен быть не короче 8 символов':
      'The password must be at least 8 characters',
  'Пароль должен содержать буквы и цифры':
      'The password must contain letters and digits',
  'Пароль изменён. Войдите с новым паролем':
      'Password changed. Sign in with the new password',
  'Пароль слишком длинный (максимум 64)':
      'The password is too long (maximum 64)',
  'Парфюм Peripera Mood': 'Peripera Mood Perfume',
  'Парфюмерия': 'Perfume',
  'Парфюмерная композиция / Parfum': 'Parfum',
  'Пенообразователи, сушат кожу': 'Foaming agents, dry the skin',
  'Пенообразователь, сушит кожу.': 'Foaming agent, dries the skin.',
  'Перейти в каталог': 'Go to catalog',
  'Персиковый': 'Peach',
  'Печатаю…': 'Typing…',
  'Пигментация': 'Pigmentation',
  'Питательный крем для тела с керамидами.':
      'Nourishing body cream with ceramides.',
  'По вашему запросу товаров нет. Измените поиск или фильтры.':
      'No products match your query. Change the search or filters.',
  'По названию': 'By name',
  'По новизне': 'Newest',
  'Повторите пароль': 'Repeat the password',
  'Повторить': 'Retry',
  'Подарки': 'Gifts',
  'Подарочный набор «Нежность»': '"Tenderness" gift set',
  'Подобрать косметику': 'Pick cosmetics',
  'Подставлены данные демо-аккаунта': 'Demo account data filled in',
  'Подтон': 'Undertone',
  'Подходящих товаров не найдено': 'No suitable products found',
  'Поиск': 'Search',
  'Поиск брендов, косметики, оттенков...':
      'Search brands, cosmetics, shades...',
  'Поиск по названию': 'Search by name',
  'Пока нет трендовых товаров': 'No trending products yet',
  'Пока никто не добавил фото. Будьте первым!':
      'Nobody has added a photo yet. Be the first!',
  'Показать все в каталоге': 'Show all in catalog',
  'Показать пароль': 'Show password',
  'Покраснение и зуд': 'Redness and itching',
  'Покупки': 'Purchases',
  'Покупок пока нет': 'No purchases yet',
  'Политика конфиденциальности': 'Privacy Policy',
  'Пользователь': 'User',
  'Помощник ещё отвечает, подождите секунду':
      'The assistant is still replying, wait a second',
  'Понятно': 'Got it',
  'Попробуйте другой запрос или название бренда':
      'Try another query or a brand name',
  'Популярное': 'Popular',
  'Популярные категории': 'Popular categories',
  'Последние отзывы': 'Latest reviews',
  'Посмотрите на вены на вашем запястье при естественном освещении.':
      'Look at the veins on your wrist in natural light.',
  'Посоветуй тинт для губ': 'Recommend a lip tint',
  'Поставьте оценку товару': 'Rate the product',
  'Потенциальные аллергены': 'Potential allergens',
  'Почти не обгораю': 'I almost never burn',
  'Превосходный состав!': 'Excellent ingredients!',
  'Придаёт сияние и пигмент.': 'Adds glow and pigment.',
  'Придумайте новый пароль для {v0}.': 'Create a new password for {v0}.',
  'Приемлемый состав': 'Acceptable ingredients',
  'Применить': 'Apply',
  'Примите условия использования': 'Accept the terms of use',
  'Приятный оттенок, но немного липкий.':
      'Pleasant shade, but slightly sticky.',
  'Проблемы кожи (фокус ухода)': 'Skin concerns (care focus)',
  'Проверьте поля формы': 'Check the form fields',
  'Продукт': 'Product',
  'Продукт нефтепереработки': 'Petroleum product',
  'Продукт нефтепереработки.': 'Petroleum product.',
  'Продукт содержит: {v0}. Людям с высокой чувствительностью рекомендуется тест на сгибе локтя.':
      'The product contains: {v0}. People with high sensitivity are advised to do a patch test on the elbow.',
  'Пройдите тест': 'Take the test',
  'Пройти бьюти-тест заново': 'Retake the beauty test',
  'Профиль': 'Profile',
  'Пудровые румяна с естественным сиянием.':
      'Powder blush with a natural glow.',
  'Пуш-уведомления о скидках': 'Push notifications about discounts',
  'Пчелиный воск / Beeswax': 'Beeswax',
  'Расскажите, как вам товар...': 'Tell us how you like the product...',
  'Реакций не было': 'No reactions',
  'Реакция добавлена в дневник': 'Reaction added to the diary',
  'Реакция на «{v0}» будет удалена из дневника.':
      'The reaction to "{v0}" will be deleted from the diary.',
  'Регистрация': 'Sign up',
  'Редактировать': 'Edit',
  'Редактировать отзыв': 'Edit review',
  'Редактировать профиль': 'Edit profile',
  'Редактировать реакцию': 'Edit reaction',
  'Результат сохранён в вашем бьюти-профиле.':
      'The result is saved in your beauty profile.',
  'Результат теста': 'Test result',
  'Результаты ({v0})': 'Results ({v0})',
  'Рейтинг магазина: ★ {v0}': 'Store rating: ★ {v0}',
  'Рекомендую: {v0}.': 'I recommend: {v0}.',
  'Рубль (₽)': 'Ruble (₽)',
  'Румяна Better Than Cheek': 'Better Than Cheek Blush',
  'Румянец': 'Blush',
  'Рыжий / медный': 'Red / copper',
  'Салициловая кислота / Salicylic Acid': 'Salicylic Acid',
  'Сбросить': 'Reset',
  'Сбросить демо-данные': 'Reset demo data',
  'Сбросить демо-данные?': 'Reset demo data?',
  'Сбросить фильтры': 'Reset filters',
  'Свернуть': 'Collapse',
  'Светлая': 'Light',
  'Светлая с румянцем': 'Fair with a blush',
  'Светло-карие': 'Light brown',
  'Светлый': 'Light',
  'Светлый блонд / русый': 'Light blond / dark blond',
  'Светлый тёплый тип: вам идут персиковые, коралловые и золотистые оттенки, лёгкие текстуры и тёплые нюды.':
      'Light warm type: peach, coral and golden shades, light textures and warm nudes suit you.',
  'Светлый холодный тип: выбирайте розовые, лавандовые и приглушённые оттенки с холодным подтоном.':
      'Light cool type: choose pink, lavender and muted shades with a cool undertone.',
  'Сделать снимок': 'Take a photo',
  'Сейчас в тренде': 'Trending now',
  'Сейчас скидок нет, но я сообщу, когда появятся.':
      'There are no discounts right now, but I will let you know when they appear.',
  'Сейчас со скидкой: {v0}.': 'On sale now: {v0}.',
  'Сентября': 'September',
  'Силикон, создаёт плёнку на коже.': 'Silicone, creates a film on the skin.',
  'Силиконы': 'Silicones',
  'Сильные высыпания': 'Severe breakouts',
  'Синие / Фиолетовые': 'Blue / purple',
  'Скрыть пароль': 'Hide password',
  'Слишком длинное название': 'The name is too long',
  'Слишком длинное название (максимум 40)': 'The name is too long (maximum 40)',
  'Слишком длинный запрос': 'The query is too long',
  'Слишком короткое название': 'The name is too short',
  'Сложные эфиры, консерванты': 'Complex esters, preservatives',
  'Слюда / Mica': 'Mica',
  'Смешанные (Оба цвета)': 'Mixed (both colors)',
  'Смуглая / тёмная': 'Dark-skinned / deep',
  'Смуглый': 'Tan',
  'Сначала войдите в аккаунт': 'Sign in first',
  'Сначала дешёвые': 'Cheapest first',
  'Сначала дорогие': 'Most expensive first',
  'Со скидкой': 'On sale',
  'Создайте бьюти-профиль, чтобы подбирать идеальную косметику.':
      'Create a beauty profile to pick the perfect cosmetics.',
  'Создают пленку, забивают поры': 'Create a film, clog pores',
  'Солнце': 'Sun',
  'Солнцезащитный крем на основе рисовых экстрактов.':
      'Sunscreen based on rice extracts.',
  'Сообщение слишком длинное (максимум 500 символов)':
      'The message is too long (maximum 500 characters)',
  'Сортировка': 'Sorting',
  'Состав вызывает вопросы': 'The ingredients raise questions',
  'Состав недоступен': 'Ingredients unavailable',
  'Состав требует внимания': 'The ingredients need attention',
  'Сохранено: {picked}': 'Saved: {picked}',
  'Сохранить': 'Save',
  'Сохранить изменения': 'Save changes',
  'Сохранить пароль': 'Save password',
  'Спасибо за покупку! Оплата и доставка в приложении имитируются.':
      'Thank you for your purchase! Payment and delivery in the app are simulated.',
  'Спасибо! Отзыв опубликован': 'Thank you! Review published',
  'Специальное предложение': 'Special offer',
  'Спирт денат. / Alcohol Denat.': 'Alcohol Denat.',
  'Список ингредиентов': 'Ingredient list',
  'Список пуст': 'The list is empty',
  'Спросите про цены, состав, скидки...':
      'Ask about prices, ingredients, discounts...',
  'Сравнение цен': 'Price comparison',
  'Сравнение цен в магазинах': 'Price comparison across stores',
  'Сравни цены Flower Knows и Peripera':
      'Compare Flower Knows and Peripera prices',
  'Сразу краснею': 'I burn right away',
  'Средний': 'Medium',
  'Статус': 'Status',
  'Стойкий аромат, но дороговат.': 'Long-lasting fragrance, but a bit pricey.',
  'Стойкий тинт для губ с эффектом сочных губ.':
      'Long-lasting lip tint with a juicy-lips effect.',
  'Сульфаты (SLS / SLES)': 'Sulfates (SLS / SLES)',
  'Сухая': 'Dry',
  'Сухость и шелушение': 'Dryness and peeling',
  'Сушит кожу, повышает проницаемость.':
      'Dries the skin, increases permeability.',
  'Сыворотка Niacinamide 10%': 'Niacinamide 10% Serum',
  'Сыворотка для лица': 'Face serum',
  'Сыворотка против расширенных пор и несовершенств.':
      'Serum against enlarged pores and imperfections.',
  'ТОН КОЖИ': 'SKIN TONE',
  'ТРЦ Dostyk Plaza': 'Dostyk Plaza Mall',
  'Тальк / Talc': 'Talc',
  'Телефон': 'Phone',
  'Тело': 'Body',
  'Тело и ванна': 'Body and bath',
  'Тема оформления': 'Theme',
  'Тенге (₸)': 'Tenge (₸)',
  'Тест на подтон кожи': 'Skin undertone test',
  'Тест цветотипа': 'Color type test',
  'Тинт Peripera Ink': 'Peripera Ink Tint',
  'Тинт для губ Flower Knows': 'Flower Knows Lip Tint',
  'Тинт с бархатным финишем и насыщенным цветом.':
      'Tint with a velvet finish and rich color.',
  'Тип кожи': 'Skin type',
  'Тип реакции': 'Reaction type',
  'Товар не найден': 'Product not found',
  'Товара нет в наличии, добавить его в корзину нельзя':
      'The product is out of stock, it cannot be added to the cart',
  'Товаров: {v0}\nИтого: {v1}\nБонусы за заказ: +{v2}':
      'Items: {v0}\nTotal: {v1}\nOrder bonuses: +{v2}',
  'Товары пока не добавлены': 'No products have been added yet',
  'Токоферол / Tocopherol': 'Tocopherol',
  'Токсичные фиксаторы запаха': 'Toxic scent fixatives',
  'Токсичные фиксаторы запаха.': 'Toxic scent fixatives.',
  'Только цифры': 'Digits only',
  'Тон кожи': 'Skin tone',
  'Тонер Heartleaf 77%': 'Heartleaf 77% Toner',
  'Триклозан': 'Triclosan',
  'Триклозан / Triclosan': 'Triclosan',
  'Тяжесть: ': 'Severity: ',
  'Тяжесть: {_severity} из 5': 'Severity: {_severity} of 5',
  'Тёмная': 'Dark',
  'Тёмно-карие / чёрные': 'Dark brown / black',
  'Тёмный': 'Dark',
  'Тёплый': 'Warm',
  'УВЕДОМЛЕНИЯ': 'NOTIFICATIONS',
  'Убрать': 'Remove',
  'Убрать из избранного': 'Remove from favorites',
  'Уведомления выключены': 'Notifications are off',
  'Уведомления выключены. Нажмите, чтобы включить их в настройках.':
      'Notifications are off. Tap to turn them on in settings.',
  'Уведомления о скидках': 'Discount notifications',
  'Уведомления о скидках включены': 'Discount notifications are on',
  'Увлажняющий компонент, удерживает влагу.':
      'Moisturizing ingredient, retains moisture.',
  'Увлажняющий крем для тела': 'Moisturizing body cream',
  'Удалено из избранного': 'Removed from favorites',
  'Удалить': 'Delete',
  'Удалить заказ №{v0}?': 'Delete order #{v0}?',
  'Удалить запись': 'Delete entry',
  'Удалить запись?': 'Delete the entry?',
  'Удалить из списка?': 'Remove from the list?',
  'Удалить отзыв?': 'Delete the review?',
  'Удалить товар?': 'Remove the item?',
  'Удалённый товар': 'Deleted product',
  'Уже есть аккаунт?': 'Already have an account?',
  'Указывает на нейтральный подтон': 'Indicates a neutral undertone',
  'Указывает на тёплый подтон': 'Indicates a warm undertone',
  'Указывает на холодный подтон': 'Indicates a cool undertone',
  'Универсальная палетка нюдовых оттенков на каждый день.':
      'A universal palette of nude shades for every day.',
  'Условия использования': 'Terms of Use',
  'Успокаивающий тонер с экстрактом хауттюйнии.':
      'Soothing toner with houttuynia extract.',
  'Уточните параметры, чтобы быстрее найти нужный товар.':
      'Refine the parameters to find the product you need faster.',
  'Уход за лицом': 'Face care',
  'Уютная палетка в тёплых розово-коричневых тонах.':
      'A cozy palette in warm pink-brown tones.',
  'Фамилия': 'Last name',
  'Февраля': 'February',
  'Фильтры': 'Filters',
  'Фильтры сброшены': 'Filters reset',
  'Формальдегид': 'Formaldehyde',
  'Формальдегид / Formaldehyde': 'Formaldehyde',
  'Фото товара от покупателей': 'Customer product photos',
  'Фталаты': 'Phthalates',
  'Фталаты / Phthalates': 'Phthalates',
  'Холодный': 'Cool',
  'Холодный розовый': 'Cool pink',
  'Цвет аватара': 'Avatar color',
  'Цветотип': 'Color type',
  'Цена': 'Price',
  'Что вы почувствовали?': 'What did you feel?',
  'Что-то пошло не так': 'Something went wrong',
  'Что-то пошло не так, попробуйте переформулировать вопрос.':
      'Something went wrong, try rephrasing your question.',
  'Чувствительная': 'Sensitive',
  'Чувствительность и покраснения': 'Sensitivity and redness',
  'Чёрный / тёмный брюнет': 'Black / dark brunette',
  'Чёрный список': 'Blacklist',
  'Шаг {v0} из {v1}': 'Step {v0} of {v1}',
  'Шампунь Perfect Serum': 'Perfect Serum Shampoo',
  'Шатен / каштановый': 'Brown / chestnut',
  'Экран недоступен': 'Screen unavailable',
  'Это действие нельзя отменить.': 'This action cannot be undone.',
  'Этот email уже используется другим аккаунтом':
      'This email is already used by another account',
  'Этот компонент уже есть в списке': 'This ingredient is already in the list',
  'Я могу сравнить цены, проверить состав, показать скидки или подобрать косметику. Например: «Посоветуй тинт для губ» или «Какой состав у палетки Flower Knows?»':
      'I can compare prices, check ingredients, show discounts or pick cosmetics. For example: "Recommend a lip tint" or "What is the composition of the Flower Knows palette?"',
  'Я согласен с ': 'I agree to the ',
  'Ягодный / бордовый': 'Berry / burgundy',
  'Язык приложения': 'App language',
  'Января': 'January',
  'вчера': 'yesterday',
  'день': 'day',
  'дней': 'days',
  'дня': 'days',
  'критический компонент': 'critical ingredient',
  'критических компонента': 'critical ingredients',
  'пр. Достык 12': '12 Dostyk Ave.',
  'тг': 'KZT',
  'только что': 'just now',
  'ул. Абая 45': '45 Abay St.',
  'условиями использования': 'terms of use',
  'час': 'hour',
  'часа': 'hours',
  'часов': 'hours',
  'магазине': 'store',
  'магазинах': 'stores',
  'отзыв': 'review',
  'отзыва': 'reviews',
  'отзывов': 'reviews',
  'Айгерим': 'Aigerim',
  'Айнара': 'Ainara',
  'Алима': 'Alima',
  'Амина': 'Amina',
  'Анастасия': 'Anastasia',
  'Динара': 'Dinara',
  'Елена': 'Elena',
  'Жанар': 'Zhanar',
  'Камила': 'Kamila',
  'Мадина': 'Madina',
  'Мария': 'Maria',
  'Марта': 'Marta',
  'София': 'Sofia',
  'Не удалось проанализировать фото.': 'Could not analyze the photo.',
  'ИИ-сервер недоступен.': 'The AI server is unavailable.',
  'ИИ отвечает слишком долго.': 'The AI is taking too long to answer.',
  'ИИ вернул ошибку. Проверьте, что модель для анализа фото установлена.':
      'The AI returned an error. Check that the photo analysis model is installed.',
  'Не удалось разобрать ответ ИИ.': 'Could not read the AI answer.',
  'Фото (по желанию)': 'Photo (optional)',
  'Естественное или нейтральное освещение': 'Natural or neutral lighting',
  'Лицо хорошо видно, без фильтров': 'Your face is clearly visible, no filters',
  'Желательно без яркого макияжа': 'Preferably without heavy makeup',
  'Смотрите прямо в камеру': 'Look straight at the camera',
  'Улучшите результат с помощью фото': 'Improve your result with a photo',
  'Фото — необязательный шаг. ИИ использует его только как дополнительную подсказку; ваши ответы важнее.':
      'The photo is an optional step. The AI uses it only as an extra hint; your answers matter more.',
  'Как сделать хорошее фото': 'How to take a good photo',
  'Ваше фото используется только для улучшения анализа бьюти-профиля и не сохраняется.':
      'Your photo is used only to improve your Beauty Profile analysis and is not stored.',
  'ИИ-сервер сейчас недоступен — анализ фото не сработает, но тест можно завершить и без него.':
      'The AI server is unavailable right now — photo analysis will not work, but you can finish the test without it.',
  'Сделать фото': 'Take a photo',
  'Пропустить': 'Skip',
  'Использовать фото': 'Use photo',
  'Переснять': 'Retake',
  'Анализируем фото…': 'Analyzing the photo…',
  'Это может занять до минуты.': 'This may take up to a minute.',
  'Ничего страшного: результат можно получить по ответам теста.':
      'No problem: the result can be based on your test answers.',
  'Продолжить без фото': 'Continue without a photo',
  'Попробовать другое фото': 'Try another photo',
  'Определено по: опросник + анализ фото':
      'Determined using: questionnaire + photo analysis',
  'Определено по: опросник': 'Determined using: questionnaire',
  'Подобрать косметику для меня': 'Find products for me',
  'Опросник + анализ фото': 'Questionnaire + photo analysis',
  'Опросник': 'Questionnaire',
  'ТИП КОЖИ': 'SKIN TYPE',
  'ЦВЕТОТИП': 'COLOR TYPE',
  'ПРОБЛЕМЫ КОЖИ': 'SKIN CONCERNS',
  'ОПРЕДЕЛЕНО ПО': 'DETERMINED USING',
  'Уверенность анализа фото: {n}%': 'Photo analysis confidence: {n}%',
  'Пройти тест заново': 'Retake the test',
  'Выберите, как ведёт себя ваша кожа': 'Choose how your skin behaves',
  'Тест: ваша кожа': 'Test: your skin',
  'Как кожа ведёт себя через пару часов после умывания?':
      'How does your skin feel a couple of hours after washing?',
  'Тип кожи определяется по вашим ответам — по фото его не угадать.':
      'Skin type comes from your answers — it cannot be guessed from a photo.',
  'Что вас беспокоит? (можно выбрать несколько)':
      'What concerns you? (you can pick several)',
  'Подбор уточнён с помощью ИИ': 'The selection was refined with AI',
  'ИИ сейчас недоступен — показан обычный персональный подбор.':
      'The AI is unavailable right now — the regular personal selection is shown.',
  'Уточнить подбор с ИИ': 'Refine the selection with AI',
  'ИИ': 'AI',
  'Тонкая водостойкая тушь для аккуратного прокрашивания каждой ресницы.':
      'A slim waterproof mascara that coats every lash neatly.',
  'Палетка из десяти матовых и сияющих оттенков для повседневного макияжа глаз.':
      'A palette of ten matte and shimmering shades for everyday eye makeup.',
  'Сияющая помада-бальзам для губ с лёгким цветом и блеском.':
      'A glowy lip balm-stick with a light tint and shine.',
  'Компактная палетка из четырёх оттенков теней: матовые и мерцающие.':
      'A compact palette of four eyeshadow shades: matte and shimmering.',
  'Лёгкая эссенция с 96% муцина улитки для увлажнения и восстановления кожи.':
      'A light essence with 96% snail mucin to hydrate and repair the skin.',
  'Мягкий пудровый аромат: груша, ирис, роза и белый мускус.':
      'A soft powdery scent: pear, iris, rose and white musk.',
  'Бархатный тинт для губ с матовым финишем и стойким цветом.':
      'A velvety lip tint with a matte finish and long-lasting colour.',
  'Глянцевый тинт для губ с эффектом сочных увлажнённых губ.':
      'A glossy lip tint for juicy, hydrated-looking lips.',
  'Блеск для губ с цветом и зеркальным эффектом.':
      'A tinted lip gloss with a mirror-like shine.',
  'Увлажняющий кушон с SPF и лёгким покрытием.':
      'A hydrating cushion with SPF and light coverage.',
  'Лёгкий солнцезащитный крем SPF50+ с рисовым экстрактом и пробиотиками.':
      'A light SPF50+ sunscreen with rice extract and probiotics.',
  'Сыворотка с 10% ниацинамида и 1% цинка для кожи с несовершенствами и расширенными порами.':
      'A serum with 10% niacinamide and 1% zinc for blemish-prone skin and enlarged pores.',
  'Пудровые румяна с естественным оттенком для нежного румянца.':
      'Powder blush with a natural shade for a soft glow.',
  'Увлажняющий крем с тремя церамидами и гиалуроновой кислотой для сухой кожи.':
      'A moisturizing cream with three ceramides and hyaluronic acid for dry skin.',
  'Лёгкий увлажняющий крем для лица, тела и рук.':
      'A light moisturizing cream for face, body and hands.',
  'Шампунь с маслами арганы и жожоба для гладких и блестящих волос.':
      'A shampoo with argan and jojoba oils for smooth, shiny hair.',
  'Успокаивающий тонер с 77% экстракта хауттюйнии для чувствительной кожи.':
      'A soothing toner with 77% houttuynia extract for sensitive skin.',
  'Полный состав (INCI)': 'Full ingredients (INCI)',
  'Источник: {v0}': 'Source: {v0}',
  'Страна производителя: не указана': 'Country of manufacture: not stated',
  'Страна производителя: {v0}': 'Country of manufacture: {v0}',
  ' (источник: {v0})': ' (source: {v0})',
  'Состав может отличаться по оттенкам и сериям: сверяйтесь с упаковкой.':
      'The formula can differ by shade and batch: check the packaging.',
  'Какой состав у крема CeraVe?': 'What is in the CeraVe cream?',
  'Сравни цены Rom&nd и Peripera': 'Compare Rom&nd and Peripera prices',
  'Парфюм': 'Perfume',
  'Уход': 'Skincare',
  'ИИ-помощник сейчас недоступен': 'The AI assistant is unavailable right now',
  'Остальные функции приложения работают.': 'The rest of the app works.',
  'Рекомендуем вам': 'Recommended for you',
  'Подойдёт ли мне этот товар?': 'Is this product right for me?',
  'Спросить ИИ: подойдёт ли мне?': 'Ask AI: is it right for me?',
  'Сервер ИИ (Ollama)': 'AI server (Ollama)',
  'Адрес сервера': 'Server address',
  'Текстовая модель': 'Text model',
  'Модель для фото': 'Photo model',
  'ИИ-сервер недоступен. Попробуйте позже.':
      'The AI server is unavailable. Try again later.',
  'Все товары уже классифицированы': 'All products are already classified',
  'Классифицировано товаров: {n}': 'Products classified: {n}',
  'Подключено': 'Connected',
  'Проверка…': 'Checking…',
  'Недоступно': 'Unavailable',
  'Адрес не задан': 'Address not set',
  'Не проверено': 'Not checked',
  'Сервер': 'Server',
  'Текстовая модель не установлена на сервере.':
      'The text model is not installed on the server.',
  'Модель для фото не установлена на сервере.':
      'The photo model is not installed on the server.',
  'Без ИИ работают тест, каталог, чёрный список и рекомендации. ИИ нужен для чата, анализа фото и уточнения подбора.':
      'The test, catalog, blacklist and recommendations work without AI. AI is needed for the chat, photo analysis and refining the selection.',
  'Проверить подключение': 'Test connection',
  'Изменить сервер и модели': 'Change server and models',
  'Классифицировать товары (ИИ)': 'Classify products (AI)',
  'Пройдите бьюти-тест, чтобы получать персональные рекомендации.':
      'Take the Beauty Test to get personal recommendations.',
  'Пройти тест': 'Take the test',
  'ИИ-АССИСТЕНТ': 'AI ASSISTANT',
  'Если реакция сильная (отёк, затруднённое дыхание, сильная сыпь, боль) — прекратите использовать средство и обратитесь к врачу.':
      'If the reaction is severe (swelling, trouble breathing, severe rash, pain), stop using the product and see a doctor.',
  'Удалить фото': 'Remove photo',
  'Фото удалено': 'Photo removed',
  'Фото профиля обновлено': 'Profile photo updated',
  '{n}% совпадение': '{n}% match',
  'Есть компоненты из вашего чёрного списка':
      'Contains ingredients from your blacklist',
  'Почему это подходит вам': 'Why it suits you',
  'Подходит вашему цветотипу: {v}': 'Matches your color type: {v}',
  'Подходит вашему подтону: {v}': 'Matches your undertone: {v}',
  'Рекомендован для типа кожи: {v}': 'Recommended for skin type: {v}',
  'Помогает при проблеме: {v}': 'Helps with: {v}',
  'Мягкий состав, без раздражающих компонентов':
      'Gentle formula, no irritating ingredients',
  'Нет активных компонентов из вашего чёрного списка':
      'No active blacklist ingredients detected',
  'Кожа стянута, появляется шелушение': 'Skin feels tight, flaking appears',
  'Комфортно, без блеска и стянутости': 'Comfortable, no shine or tightness',
  'Блестит по всему лицу': 'Shiny all over the face',
  'Блестит только Т-зона': 'Shiny only in the T-zone',
  'Появляется покраснение или раздражение': 'Redness or irritation appears',
  'Для вас': 'For you',
  'Введите email, указанный при регистрации, и мы отправим код для восстановления доступа.':
      'Enter the email you registered with and we will send a code to restore access.',
  'Запись о покупке будет удалена из истории, бонусы за неё пересчитаются.':
      'The purchase will be removed from the history and its bonus points recalculated.',
  'Мы отправили код подтверждения на {v0}.\n\nПриложение работает без сервера, поэтому письмо имитируется. Ваш код: {v1}\n\nВведите его на следующем экране и задайте новый пароль.':
      'We sent a confirmation code to {v0}.\n\nThe app works without a server, so the email is simulated. Your code: {v1}\n\nEnter it on the next screen and set a new password.',
  'Отправить код': 'Send code',
  'Код отправлен': 'Code sent',
  'Код из письма': 'Code from the email',
  'Введите 6-значный код': 'Enter the 6-digit code',
  'Код устарел. Запросите новый': 'The code has expired. Request a new one',
  'Неверный код': 'Wrong code',
  'Пользователь с таким email уже существует':
      'A user with this email already exists',
  'Списать бонусы: −{v0}': 'Spend bonus points: −{v0}',
  'Товаров: {v0}\nСписано бонусов: −{v3}\nИтого: {v1}\nБонусы за заказ: +{v2}':
      'Items: {v0}\nBonus points spent: −{v3}\nTotal: {v1}\nBonus points for the order: +{v2}',
  '+{v0} бонусов, −{v1} списано': '+{v0} bonus points, −{v1} spent',
  'Списано бонусов': 'Bonus points spent',
  '«{v0}» будет удалено из косметички и из плана ухода. История применения сохранится.':
      '“{v0}” will be removed from your cosmetic bag and care plan. The usage history is kept.',
  '«{v0}» относится к группе «{v1}», которую вы внесли в чёрный список.':
      '“{v0}” belongs to the group “{v1}” that you put on your blacklist.',
  'Адрес сервера ИИ не задан': 'The AI server address is not set',
  'Бренд (необязательно)': 'Brand (optional)',
  'В названии есть компонент «{v1}», который вы добавили в чёрный список.':
      'The name contains “{v1}”, a component you added to your blacklist.',
  'В чёрном списке нет включённых компонентов, поэтому сравнивать не с чем.':
      'No components are switched on in your blacklist, so there is nothing to compare with.',
  'ВЕЧЕР': 'EVENING',
  'Введите название средства': 'Enter the product name',
  'Введите состав или выберите фото': 'Enter the ingredients or choose a photo',
  'Вечер': 'Evening',
  'Вечерний уход': 'Evening care',
  'Все ваши средства уже в этом плане':
      'All your products are already in this plan',
  'Все компоненты ({n})': 'All components ({n})',
  'Вскрыто раньше, чем куплено? Проверьте даты':
      'Opened before it was bought? Check the dates',
  'Вскрыто: {v0}': 'Opened: {v0}',
  'Вы отмечали реакцию на это средство (тяжесть {v} из 5), поэтому оно ниже в рекомендациях':
      'You noted a reaction to this product (severity {v} of 5), so it is lower in the recommendations',
  'Выберите категорию': 'Choose a category',
  'Выберите средство из косметички': 'Choose a product from your cosmetic bag',
  'Выбрать из каталога (необязательно)': 'Pick from the catalog (optional)',
  'Выбрать фото из галереи': 'Choose a photo from the gallery',
  'Выше': 'Move up',
  'Годен до': 'Best before',
  'Годен до (дата на упаковке)': 'Best before (date on the package)',
  'Дата вскрытия': 'Date opened',
  'Дата вскрытия не может быть в будущем':
      'The opening date can not be in the future',
  'Дата покупки': 'Purchase date',
  'Дата покупки не может быть в будущем':
      'The purchase date can not be in the future',
  'Дата: {a} → {b}': 'Date: {a} → {b}',
  'Добавить в косметичку': 'Add to my cosmetic bag',
  'Добавить средство': 'Add a product',
  'Добавить средство в план': 'Add a product to the plan',
  'Добавить фото': 'Add a photo',
  'Добавьте средства из косметички в том порядке, в котором вы ими пользуетесь.':
      'Add products from your cosmetic bag in the order you use them.',
  'Добавьте средства, которые у вас уже есть, чтобы составить план ухода и следить за сроками.':
      'Add the products you already have to build a care plan and keep an eye on expiry dates.',
  'Другое средство — ввести вручную': 'Another product: enter manually',
  'Заметка изменена': 'Note changed',
  'Запись создана': 'Record created',
  'ИИ вернул ошибку. Попробуйте ещё раз позже.':
      'The AI returned an error. Please try again later.',
  'ИИ перегружен или лимит исчерпан. Попробуйте позже.':
      'The AI is busy or the limit is used up. Try again later.',
  'ИИ-помощник не успел ответить': 'The AI assistant did not answer in time',
  'ИИ-помощник перегружен или лимит исчерпан':
      'The AI assistant is busy or its limit is used up',
  'Изменений пока нет.': 'No changes yet.',
  'Изменить адрес сервера': 'Change the server address',
  'Использовать до {v0} (осталось {v1} {v2})':
      'Use until {v0} ({v1} {v2} left)',
  'История изменений': 'Change history',
  'История пока пуста': 'The history is empty so far',
  'История ухода': 'Care history',
  'Камера недоступна (в симуляторе камеры нет). Выберите фото из галереи или введите состав вручную.':
      'The camera is not available (the simulator has no camera). Choose a photo from the gallery or type the ingredients.',
  'Компонент «{v0}» есть в составе {v1} из {v2} средств с записями.':
      'The component “{v0}” is in {v1} of {v2} products with entries.',
  'Компоненты разделяйте запятыми.': 'Separate components with commas.',
  'Косметичка пуста': 'Your cosmetic bag is empty',
  'Куплено: {v0}': 'Bought: {v0}',
  'Личные предпочтения': 'Personal preferences',
  'Модель': 'Model',
  'Мои средства': 'My products',
  'Мой уход': 'My care',
  'Моя косметичка': 'My cosmetic bag',
  'Моё средство': 'My product',
  'Название': 'Name',
  'Найдено совпадений с чёрным списком: {n}': 'Blacklist matches found: {n}',
  'Напоминание основано на данных упаковки, которые вы ввели. Это не медицинская рекомендация.':
      'The reminder is based on the package data you entered. It is not medical advice.',
  'Например, увлажняющий крем': 'For example, a moisturizing cream',
  'Не вскрыто': 'Not opened',
  'Не знаю': 'I don\'t know',
  'Не удалось открыть галерею. Проверьте доступ к фото.':
      'Could not open the gallery. Check the access to photos.',
  'Не удалось прочитать состав на фото. Попробуйте сфотографировать ближе и при хорошем освещении или введите состав вручную.':
      'Could not read the ingredients in the photo. Try a closer photo in good light, or type the ingredients.',
  'Не удалось сохранить средство': 'Could not save the product',
  'Не указана': 'Not set',
  'Ниже': 'Move down',
  'Открыть чёрный список': 'Open the blacklist',
  'Отмечайте использованные средства в плане ухода, и они появятся здесь.':
      'Mark the products you used in your care plan and they will appear here.',
  'Отправить фото в ИИ?': 'Send the photo to the AI?',
  'Отправлять ИИ Beauty-профиль и чёрный список':
      'Send my Beauty profile and blacklist to the AI',
  'Очистить дату': 'Clear the date',
  'План пока пуст': 'The plan is empty so far',
  'Повторяющиеся наблюдения': 'Repeated observations',
  'Попробуйте через {n} с.': 'Try again in {n} s.',
  'Попробуйте чуть позже.': 'Please try a little later.',
  'Предпочтения слегка меняют порядок рекомендаций, но не скрывают товары.':
      'Preferences slightly change the order of recommendations but never hide products.',
  'Проверить по чёрному списку': 'Check against the blacklist',
  'Проверка идёт только по вашему чёрному списку и по известным названиям компонентов, редкие названия она может пропустить. Это не гарантия отсутствия аллергии и не медицинское заключение.':
      'The check uses only your blacklist and well-known component names, so rare names can be missed. It is not a guarantee against allergies and not a medical opinion.',
  'Проверка состава': 'Ingredient check',
  'Продукт: {a} → {b}': 'Product: {a} → {b}',
  'Разрешить': 'Allow',
  'Разрешить ИИ видеть ваш Beauty-профиль и чёрный список, чтобы советы были точнее? Они будут отправлены на сервер ИИ. Фото и контакты не отправляются. Это можно изменить в Настройках.':
      'Allow the AI to see your Beauty profile and blacklist so the advice is more accurate? They will be sent to the AI server. Photos and contact details are not sent. You can change this in Settings.',
  'Разрешить отправку фото в ИИ': 'Allow sending photos to the AI',
  'Распознавание текста недоступно на этом устройстве. Введите состав вручную.':
      'Text recognition is not available on this device. Type the ingredients by hand.',
  'Реакция: {a} → {b}': 'Reaction: {a} → {b}',
  'Режим': 'Mode',
  'Результат': 'Result',
  'Сегодня отмечено: {v0} из {v1}': 'Marked today: {v0} of {v1}',
  'Сервер ИИ': 'AI server',
  'Скоро истекает: осталось {v1} {v2} (до {v0})':
      'Expires soon: {v1} {v2} left (until {v0})',
  'Сначала добавьте средства в «Мою косметичку».':
      'First add products to “My cosmetic bag”.',
  'Совпадений с вашим чёрным списком не найдено.':
      'No matches with your blacklist were found.',
  'Содержит «{v}», который есть и в средствах с вашими реакциями (возможно, совпадение)':
      'Contains “{v}”, which is also in products with your reactions (possibly a coincidence)',
  'Соответствует вашему предпочтению: {v}': 'Matches your preference: {v}',
  'Состав (проверьте и исправьте)': 'Ingredients (check and correct)',
  'Состав распознан. Проверьте список: распознавание может ошибаться.':
      'Ingredients recognized. Check the list: recognition can make mistakes.',
  'Средства, на которые вы отмечали реакцию, будут ниже в рекомендациях. Данные остаются на телефоне.':
      'Products you noted a reaction to will rank lower in recommendations. The data stays on your phone.',
  'Средство «{v0}» встречается в дневнике {v1} {v2} ({v3} — {v4}), средняя тяжесть {v5} из 5.':
      'The product “{v0}” appears in the diary {v1} {v2} ({v3} to {v4}), average severity {v5} of 5.',
  'Средство добавлено': 'Product added',
  'Средство удалено': 'Product deleted',
  'Срок использования заканчивается сегодня': 'The use-by date is today',
  'Срок использования истёк': 'The use-by date has passed',
  'Срок использования истёк {v0}': 'The use-by date passed on {v0}',
  'Срок использования на исходе или истёк: {n}':
      'Products near or past their use-by date: {n}',
  'Срок не указан: добавьте дату вскрытия и срок после вскрытия (значок банки на упаковке)':
      'No shelf life yet: add the opening date and the period after opening (the jar symbol on the package)',
  'Срок после вскрытия (значок банки на упаковке)':
      'Period after opening (the jar symbol on the package)',
  'Сфотографируйте состав на упаковке или выберите фото. Текст читается на телефоне: фото никуда не отправляется и не сохраняется.':
      'Photograph the ingredients on the package or choose a photo. The text is read on your phone: the photo is not sent anywhere or saved.',
  'Тестовый режим (ключа нет)': 'Test mode (no key)',
  'Тестовый режим: ключ ИИ на сервере не задан, ответы ненастоящие.':
      'Test mode: the AI key is not set on the server, the answers are not real.',
  'Тестовый режим: на сервере нет ключа ИИ, ответы помечены как ненастоящие.':
      'Test mode: the server has no AI key, answers are marked as not real.',
  'Токен приложения (необязательно)': 'App token (optional)',
  'Тяжесть: {a} → {b}': 'Severity: {a} → {b}',
  'УТРО': 'MORNING',
  'Убрать из плана': 'Remove from the plan',
  'Убрать фото': 'Remove the photo',
  'Удалить средство?': 'Delete the product?',
  'Укажите дату вскрытия, чтобы считать срок после вскрытия':
      'Enter the opening date to count the period after opening',
  'Укажите его в Кабинет → Настройки → ИИ-ассистент.':
      'Set it in Profile → Settings → AI assistant.',
  'Утренний и вечерний уход': 'Morning and evening care',
  'Утренний уход': 'Morning care',
  'Утро': 'Morning',
  'Учитывать ваши данные?': 'Use your data?',
  'Учитывать мои реакции и косметичку':
      'Take my reactions and cosmetic bag into account',
  'Фото (необязательно)': 'Photo (optional)',
  'Фото будет отправлено на сервер ИИ только для анализа цветотипа и сразу удалено с телефона. Согласие можно отозвать в Настройках.':
      'The photo will be sent to the AI server only to analyze your color type and is deleted from the phone right after. You can withdraw your consent in Settings.',
  'Фото добавлено': 'Photo added',
  'Фото заменено': 'Photo replaced',
  'Фото хранится только на этом телефоне и никуда не отправляется.':
      'The photo is stored only on this phone and is not sent anywhere.',
  'Читаю текст на фото…': 'Reading the text in the photo…',
  'Это ваш личный план, а не медицинская рекомендация. Схема не обязана быть одинаковой для всех: ориентируйтесь на состояние кожи. При раздражении прекратите использование и обратитесь к специалисту.':
      'This is your personal plan, not medical advice. A routine does not have to be the same for everyone: go by how your skin feels. If irritation appears, stop using the product and see a specialist.',
  'Это наблюдения по вашим записям, а не вывод о причине: совпадение по времени или по составу не доказывает, что реакцию вызвало именно это средство. При сильной или затяжной реакции обратитесь к врачу.':
      'These are observations from your own records, not a conclusion about the cause: a coincidence in time or composition does not prove that this product caused the reaction. See a doctor if a reaction is strong or lasts long.',
  'Это средство уже в плане': 'This product is already in the plan',
  'Это средство уже есть в вашей косметичке':
      'You already have this product in your cosmetic bag',
  'Косметичка': 'Cosmetic bag',
  'Рекомендации': 'Recommendations',
  'Без отдушки': 'Fragrance-free',
  'Натуральный состав': 'Natural composition',
  'раз': 'time',
  'раза': 'times',
  'Кислоты': 'Acids',
  'Активные компоненты': 'Active ingredients',
  'Без': 'Free of',
  'Состав': 'Composition',
  'Состав:': 'Ingredients:',
  'Ищем по опубликованному списку INCI. Число рядом: сколько товаров подходит.':
      'We search the published INCI list. The number shows how many products match.',
  'Все выбранные': 'All selected',
  'Любой из выбранных': 'Any of the selected',
  'Ключевые компоненты': 'Key ingredients',
  'Гиалуроновая кислота': 'Hyaluronic acid',
  'Салициловая кислота (BHA)': 'Salicylic acid (BHA)',
  'Гликолевая кислота (AHA)': 'Glycolic acid (AHA)',
  'Молочная кислота (AHA)': 'Lactic acid (AHA)',
  'Азелаиновая кислота': 'Azelaic acid',
  'Миндальная кислота': 'Mandelic acid',
  'Витамин C (аскорбиновая кислота)': 'Vitamin C (ascorbic acid)',
  'Транексамовая кислота': 'Tranexamic acid',
  'PHA (глюконолактон)': 'PHA (gluconolactone)',
  'Ниацинамид (B3)': 'Niacinamide (B3)',
  'Ретинол и ретиноиды': 'Retinol and retinoids',
  'Пантенол (B5)': 'Panthenol (B5)',
  'Церамиды': 'Ceramides',
  'Пептиды': 'Peptides',
  'Центелла азиатская': 'Centella asiatica',
  'Цинк': 'Zinc',
  'Сквалан': 'Squalane',
  'Муцин улитки': 'Snail mucin',
  'Глицерин': 'Glycerin',
  'Аллантоин': 'Allantoin',
  'Бета-глюкан': 'Beta-glucan',
  'Витамин E (токоферол)': 'Vitamin E (tocopherol)',
  'Хауттюйния': 'Houttuynia',
  'Ферменты и пробиотики': 'Ferments and probiotics',
  'УФ-фильтры (SPF)': 'UV filters (SPF)',
  'Без спирта': 'Alcohol-free',
  'Без парабенов': 'Paraben-free',
  'Без силиконов': 'Silicone-free',
  'Без сульфатов': 'Sulfate-free',
  'Коралл': 'Coral',
  'Тёплый розовый': 'Warm pink',
  'Золотистый беж': 'Golden beige',
  'Абрикос': 'Apricot',
  'Тёплый красный': 'Warm red',
  'Карамельный нюд': 'Caramel nude',
  'Тёмный винный': 'Dark wine',
  'Серо-коричневый': 'Gray-brown',
  'Холодный бордо': 'Cool burgundy',
  'Пудровая роза': 'Powder rose',
  'Лаванда': 'Lavender',
  'Мягкая малина': 'Soft raspberry',
  'Холодный нюд': 'Cool nude',
  'Серо-голубой': 'Gray-blue',
  'Сливочно-розовый': 'Creamy pink',
  'Оранжевый': 'Orange',
  'Горчичный': 'Mustard',
  'Тёплый коричневый': 'Warm brown',
  'Терракота': 'Terracotta',
  'Кирпичный': 'Brick',
  'Бронза': 'Bronze',
  'Карамель': 'Caramel',
  'Оливковый': 'Olive',
  'Медный коралл': 'Copper coral',
  'Фуксия': 'Fuchsia',
  'Серебристо-серый': 'Silver gray',
  'Винный': 'Wine',
  'Малиновый': 'Raspberry',
  'Холодный красный': 'Cool red',
  'Сливовый': 'Plum',
  'Ягодный': 'Berry',
  'Графит': 'Graphite',
  'Золотисто-оранжевый': 'Golden orange',
  'Тёплый беж': 'Warm beige',
  'Лучше избегать': 'Better to avoid',
  'Из каталога вам идут': 'From the catalog, these suit you',
  'Оттенок близок к вашей палитре: {v}':
      'The shade is close to your palette: {v}',
  'Оттенок ближе к палитре «{v}»: вам могут подойти другие':
      'The shade is closer to the «{v}» palette: other shades may suit you better',
  'Оттенок близок к вашему тону кожи: {v}':
      'The shade is close to your skin tone: {v}',
  'Оттенок может не совпасть с вашим тоном кожи: {v}':
      'The shade may not match your skin tone: {v}',
  'ИИ не видит результаты вашего теста, поэтому советы по цветотипу и коже будут общими.':
      'The AI cannot see your test results, so advice on color type and skin will be general.',
  'Что подойдёт моему цветотипу?': 'What suits my color type?',
  'Где есть ниацинамид?': 'Which products have niacinamide?',
  'Украшения': 'Jewelry',
  'Контраст': 'Contrast',
  'Белое': 'White',
  'Какой металл смотрится на вас лучше?': 'Which metal looks better on you?',
  'Серебро': 'Silver',
  'Золото': 'Gold',
  'Розовое золото': 'Rose gold',
  'Одинаково хорошо': 'Equally good',
  'Насколько заметна разница между цветом волос, глаз и кожи?':
      'How noticeable is the difference between your hair, eyes and skin?',
  'Очень контрастно': 'Very high contrast',
  'Средне': 'Medium',
  'Мягко, всё сливается': 'Soft, everything blends',
  'Что вам больше идёт: чисто-белое или кремовое?':
      'What suits you better: pure white or cream?',
  'Чисто-белое': 'Pure white',
  'Кремовое, слоновая кость': 'Cream, ivory',
  'Без разницы': 'No difference',
  'Лососёвый': 'Salmon',
  'Персиковый румянец': 'Peach blush',
  'Коралловый румянец': 'Coral blush',
  'Тёплая роза': 'Warm rose',
  'Золотистый абрикос': 'Golden apricot',
  'Персик': 'Peach',
  'Бирюзовый': 'Turquoise',
  'Салатовый оливковый': 'Lime olive',
  'Шампань': 'Champagne',
  'Слоновая кость': 'Ivory',
  'Бирюза': 'Turquoise',
  'Яркий коралл': 'Bright coral',
  'Светло-зелёный': 'Light green',
  'Золотисто-жёлтый': 'Golden yellow',
  'Тёплый голубой': 'Warm blue',
  'Жёлтое золото': 'Yellow gold',
  'Светлая латунь': 'Light brass',
  'Чисто-чёрный': 'Pure black',
  'Розово-лиловый': 'Pink-lilac',
  'Ягодный нюд': 'Berry nude',
  'Мягкая вишня': 'Soft cherry',
  'Холодная роза': 'Cool rose',
  'Розово-бежевый': 'Pink-beige',
  'Лавандовый румянец': 'Lavender blush',
  'Малиновая дымка': 'Raspberry haze',
  'Серо-коричневый тауп': 'Gray-brown taupe',
  'Мягкий серый': 'Soft gray',
  'Дымчатая слива': 'Smoky plum',
  'Розовый беж': 'Pink beige',
  'Пудрово-голубой': 'Powder blue',
  'Сиреневый': 'Lilac',
  'Нежно-розовый': 'Soft pink',
  'Голубая сталь': 'Steel blue',
  'Пыльная роза': 'Dusty rose',
  'Мягкий белый': 'Soft white',
  'Серый графит': 'Graphite gray',
  'Коричневый нюд': 'Brown nude',
  'Ржавый красный': 'Rust red',
  'Бордово-коричневый': 'Burgundy brown',
  'Персиково-терракотовый': 'Peach terracotta',
  'Кирпично-розовый': 'Brick pink',
  'Бронзовый румянец': 'Bronze blush',
  'Тёплый абрикос': 'Warm apricot',
  'Шоколад': 'Chocolate',
  'Медный': 'Copper',
  'Хвойный зелёный': 'Pine green',
  'Золотисто-коричневый': 'Golden brown',
  'Хаки': 'Khaki',
  'Верблюжий': 'Camel',
  'Ржавый': 'Rust',
  'Бирюзово-зелёный': 'Teal green',
  'Шоколадный': 'Chocolate brown',
  'Кремовый': 'Cream',
  'Медь': 'Copper',
  'Ледяной голубой': 'Icy blue',
  'Истинный красный': 'True red',
  'Вишнёвый': 'Cherry',
  'Яркий розовый': 'Bright pink',
  'Ягодный румянец': 'Berry blush',
  'Малиново-розовый': 'Raspberry pink',
  'Ледяная роза': 'Icy rose',
  'Тёмно-синий': 'Navy',
  'Изумруд': 'Emerald',
  'Чёрный': 'Black',
  'Ледяной лиловый': 'Icy lilac',
  'Чисто-белый': 'Pure white',
  'Королевский синий': 'Royal blue',
  'Изумрудный': 'Emerald green',
  'Холодный серый': 'Cool gray',
  'Платина': 'Platinum',
  'Белое золото': 'White gold',
  'Помада и тинты': 'Lipsticks and tints',
  'Румяна': 'Blush',
  'Тени для век': 'Eyeshadow',
  'Одежда и аксессуары': 'Clothes and accessories',
  'Металл украшений': 'Jewelry metal',
  'Палитры всех цветотипов': 'Palettes of all color types',
  'Палитры цветотипов': 'Color type palettes',
  'Это ваш цветотип': 'This is your color type',
  'Светлый, тёплый, чистый': 'Light, warm, clear',
  'Светлый, холодный, мягкий': 'Light, cool, soft',
  'Глубокий, тёплый, мягкий': 'Deep, warm, soft',
  'Глубокий, холодный, контрастный': 'Deep, cool, high contrast',
  'Выберите вариант или нажмите «Не знаю»':
      'Pick an option or tap “I don\'t know”',
  'Не знаю — пропустить': 'I don\'t know — skip',
  'Не знаете ответов? ИИ определит цветотип по фото за вас':
      'Not sure about the answers? The AI will determine your color type from a photo',
  'Не уверена': 'Not sure',
  'Подтон определят другие ответы или ИИ по фото':
      'Other answers or the AI photo analysis will decide the undertone',
  'Маловато ответов': 'Too few answers',
  'Вы ответили на {v0} из {v1} вопросов. Цветотип лучше определить по фото: ИИ посмотрит на вас и подберёт его сам. Продолжить?':
      'You answered {v0} of {v1} questions. It is better to determine the color type from a photo: the AI will look at you and choose it. Continue?',
  'Определить по фото': 'Determine from a photo',
  'Фото для ИИ': 'Photo for the AI',
  'ИИ определит цветотип по фото':
      'The AI will determine your color type from a photo',
  'Вы пропустили много вопросов, поэтому ИИ посмотрит на фото и сам определит цветотип, подтон и тон кожи.':
      'You skipped many questions, so the AI will look at the photo and determine your color type, undertone and skin tone itself.',
  'ИИ не смог уверенно определить цветотип по этому фото.':
      'The AI could not confidently determine the color type from this photo.',
  'Попробуйте другое фото при дневном свете или ответьте на вопросы теста.':
      'Try another photo in daylight or answer the test questions.',
  'Вернуться к вопросам': 'Back to the questions',
  'Магазины рядом': 'Nearby shops',
  'Где купить': 'Where to buy',
  'Карта': 'Map',
  'Нет подходящих магазинов': 'No matching shops',
  'Измените фильтры': 'Change the filters',
  'Определяем ваше положение…': 'Finding your position…',
  'Расстояния считаются от вашего положения':
      'Distances are counted from your position',
  'Геолокация недоступна: расстояния считаются от центра Астаны':
      'Location is unavailable: distances are counted from the center of Astana',
  'Адреса и часы работы настоящие, а цены и наличие демонстрационные: у магазинов нет открытых данных. Перед визитом уточните по телефону.':
      'Addresses and opening hours are real, but prices and stock are demo values: the shops publish no open data. Check by phone before you go.',
  'В наличии · {v0} шт.': 'In stock · {v0} pcs',
  'Мало · {v0} шт.': 'Few left · {v0} pcs',
  'демо-данные': 'demo data',
  'обновлено {v0}': 'updated {v0}',
  'Адрес: {v0}': 'Address: {v0}',
  'открыто до {v0}': 'open until {v0}',
  'закрыто, откроется в {v0}': 'closed, opens at {v0}',
  'Мало': 'Few',
  'Показать на карте': 'Show on the map',
  'Где купить рядом: карта': 'Where to buy nearby: map',
  'и ещё {v0} магазинов': 'and {v0} more shops',
  'Магазины на карте': 'Shops on the map',
  'Подружка, Диона и другие рядом с вами':
      'Podruzhka, Diona and others near you',
  'Где купить Niacinamide рядом со мной?':
      'Where can I buy Niacinamide near me?',
  'Диона': 'Diona',
  'MonAmie': 'MonAmie',
  'Подружка': 'Podruzhka',
  'The Face Shop': 'The Face Shop',
  'Ежедневно 10:00–22:00': 'Daily 10:00–22:00',
  'Ежедневно 10:00–21:00': 'Daily 10:00–21:00',
  'Ежедневно 09:00–22:00': 'Daily 09:00–22:00',
  'OpenStreetMap': 'OpenStreetMap',
  'Адрес из открытых объявлений сети (не проверен)':
      'Address from the chain\'s public job ads (unverified)',
  'пр. Сарыарка, 15': 'Saryarka Ave., 15',
  'пр. Кабанбай батыра, 62': 'Kabanbay Batyr Ave., 62',
  'ул. Кенесары, 42': 'Kenesary St., 42',
  'ул. Ильяса Есенберлина, 24': 'Ilyas Yesenberlin St., 24',
  'ул. Жумабека Ташенова, 23': 'Zhumabek Tashenov St., 23',
  'пр. Республики, 15': 'Respublika Ave., 15',
  'ул. Жирентаева': 'Zhirentayev St.',
  'ул. Кенесары, 64': 'Kenesary St., 64',
  'пр. Республики, 8': 'Respublika Ave., 8',
  'пр. Кабанбай батыра, 21': 'Kabanbay Batyr Ave., 21',
  'пр. Нургисы Тлендиева, 12а (ТЦ Коктал)':
      'Nurgisa Tlendiyev Ave., 12a (Koktal mall)',
  'ул. Сыганак, 17Б': 'Syganak St., 17B',
  'пр. Кабанбай батыра, 58Б': 'Kabanbay Batyr Ave., 58B',
  'Тёмный бордо': 'Dark burgundy',
  'Есть альтернативы подешевле рядом?':
      'Are there cheaper alternatives nearby?',
  '«{u}» на силиконах под «{f}» на воде: основа может скатываться и ложиться пятнами. Лучше крем на водной основе или основа на силиконах.':
      '“{u}” is silicone-based under “{f}” which is water-based: the foundation can ball up and go on patchy. Better a water-based cream or a silicone-based foundation.',
  '«{u}» на маслах под «{f}» на воде: тон ложится неровно, возможны полосы. Дайте крему полностью впитаться.':
      '“{u}” is oil-based under “{f}” which is water-based: the foundation goes on unevenly, streaks are possible. Let the cream absorb completely.',
  'на воде': 'water-based',
  'на силиконах': 'silicone-based',
  'на маслах': 'oil-based',
  'Формула: {v0}': 'Formula: {v0}',
  'Бензоилпероксид': 'Benzoyl peroxide',
  'Совместимость средств': 'Product compatibility',
  'Не используйте эти средства вместе': 'Do not use these products together',
  'Перед покупкой': 'Before you buy',
  'Сочетание с вашим уходом': 'How it goes with your care',
  'С чем сочетать': 'What to pair it with',
  'Основа {v0}: эти средства из каталога ложатся под неё ровно, без скольжения и катышков.':
      'The foundation is {v0}: these products from the catalog sit evenly under it, with no sliding or pilling.',
  'Возможный конфликт': 'Possible conflict',
  'Добавить в план всё равно?': 'Add to the plan anyway?',
  'Тонер с 7% гликолевой кислоты для мягкого отшелушивания и сияния кожи.':
      'Toner with 7% glycolic acid for gentle exfoliation and glowing skin.',
  'Безводная сыворотка с 0,5% чистого ретинола в сквалане для вечернего ухода.':
      'Water-free serum with 0.5% pure retinol in squalane for evening care.',
  'Лёгкий лосьон с бетаин салицилатом (BHA) для очищения пор и ухода за чёрными точками.':
      'Light lotion with betaine salicylate (BHA) to clear pores and care for blackheads.',
  'Сыворотка с витамином C (аскорбиновая кислота) и центеллой для сияния кожи.':
      'Serum with vitamin C (ascorbic acid) and centella for glowing skin.',
  'Убрать одну': 'Remove one',
  'Добавить ещё': 'Add one more',
  '{v0} в корзине': '{v0} in cart',
  'Карта на весь экран': 'Full-screen map',
  'Свернуть карту': 'Collapse the map',
  'Моё положение': 'My location',
  'Из чёрного списка ничего не найдено':
      'Nothing from your blacklist was found',
  'Проверено компонентов: {n}': 'Ingredients checked: {n}',
  '{v0}: найдено ({v1})': '{v0}: found ({v1})',
  '{v0}: не найдено': '{v0}: not found',
  'Десять чистых глиттеров без матовых оттенков: прозрачный опал, шампань, розовое золото и ледяная сирень.':
      'Ten pure glitters and no mattes: clear opal, champagne, rose gold and iced lilac.',
  'Персиковые, коралловые и золотисто-шампанские оттенки на тёплой слоновой кости: яркие тона поздней весны.':
      'Peach, coral and champagne gold over warm ivory: bright shades that bloom like late spring.',
  'Карамель, корица и жидкое золото, переходящие в шоколад: сияние золотого часа.':
      'Caramel, cinnamon and molten gold deepening into chocolate for a golden hour glow.',
  'Пыльная роза, мальва и мягкий розово-бежевый: прохладное спокойствие и романтичный финиш.':
      'Dusty rose, mauve and soft pink beige: cool-toned calm with a quietly romantic finish.',
  'Фуксия, слива и ледяная лаванда на холодных розовых: самая смелая палетка для вечера.':
      'Fuchsia, plum and iced lavender against cool pinks: the boldest garden, made for evening.',
  'Глянцевый тинт для губ нежно-розового оттенка с эффектом сочных увлажнённых губ.':
      'Glossy lip tint in a soft rose shade with a juicy, moisturised look.',
  'Стойкий глянцевый тинт персиково-нюдового оттенка: блеск, как глазурь на фруктах.':
      'Long-wearing glossy tint in a peachy nude shade, with a glaze-like shine.',
  'Нежные румяна в компактной коробочке тёплого персикового оттенка для естественного румянца.':
      'Soft blush in a compact case, a warm peach shade for a natural flush.',
  'Лёгкая сыворотка с низкомолекулярной гиалуроновой кислотой для глубокого увлажнения.':
      'Light serum with low-molecular hyaluronic acid for deep hydration.',
  'Успокаивающая ампула с экстрактом центеллы азиатской для чувствительной и раздражённой кожи.':
      'Soothing ampoule with Centella asiatica extract for sensitive and irritated skin.',
  'Сыворотка с прополисом и ниацинамидом для сияния кожи и баланса себума.':
      'Serum with propolis and niacinamide for glowing skin and balanced sebum.',
  'Лёгкий тонер с гиалуроновой кислотой для мгновенного увлажнения.':
      'Light toner with hyaluronic acid for instant hydration.',
  'Мягкий тонер с глубинной морской водой для ежедневного ухода без раздражения.':
      'Gentle toner with deep sea water for everyday care without irritation.',
  'Ночная маска для губ: увлажняет, смягчает и восстанавливает кожу губ за ночь.':
      'Overnight lip mask that moisturises, softens and restores the lips.',
  'Мягкий гель для умывания с pH около 5,5 для ежедневного очищения кожи.':
      'Gentle gel cleanser with a pH of about 5.5 for everyday cleansing.',
  'Питательный крем с керамидами восстанавливает барьер и смягчает сухую кожу.':
      'Nourishing cream with ceramides that restores the barrier and softens dry skin.',
  'Другие оттенки': 'Other shades',
  'Оттенок: {v0}': 'Shade: {v0}',
  'Год рождения (необязательно)': 'Year of birth (optional)',
  'Введите год рождения, например 2000':
      'Enter a year of birth, for example 2000',
  'Как кожа сейчас после умывания?':
      'How does your skin feel after washing now?',
  'Кожа меняется: проверьте, не стала ли она суше. Ответ обновит подбор и предупреждения.':
      'Skin changes: check whether it has become drier. Your answer updates the picks and the warnings.',
  'Тип кожи: {t}': 'Skin type: {t}',
  '«{a}» и «{b}»: ретиноиды и кислоты лучше разнести по времени или дням: используйте их в разные дни или вечера.':
      '“{a}” and “{b}”: retinoids and acids are better kept apart in time or on different days: use them on different days or evenings.',
  '«{a}» и «{b}»: ретиноиды и витамин C (аскорбиновая кислота) лучше разнести: витамин C утром, ретиноид вечером.':
      '“{a}” and “{b}”: retinoids and vitamin C (ascorbic acid) are better kept apart: vitamin C in the morning, the retinoid in the evening.',
  '«{a}» и «{b}»: витамин C (аскорбиновая кислота) и кислоты лучше разнести по времени или дням: витамин C утром, кислоты вечером.':
      '“{a}” and “{b}”: vitamin C (ascorbic acid) and acids are better kept apart in time or on different days: vitamin C in the morning, acids in the evening.',
  '«{a}» и «{b}»: сочетайте с осторожностью: несколько кислот могут усилить сухость, жжение или раздражение. Не наслаивайте их сразу.':
      '“{a}” and “{b}”: combine with care: several acids can increase dryness, stinging or irritation. Do not layer them right away.',
  'Это средство с ретиноидом или бензоилпероксидом не подходит в вашем возрасте. Спросите врача.':
      'This product with a retinoid or benzoyl peroxide is not suitable for your age. Ask a doctor.',
  '«{a}» содержит ретиноид или бензоилпероксид: детям до {n} лет их не предлагают. Спросите врача.':
      '“{a}” contains a retinoid or benzoyl peroxide: they are not offered to children under {n}. Ask a doctor.',
  '«{a}» содержит кислоту: возрастных рекомендаций для детей до {n} лет мы не нашли, сначала спросите врача.':
      '“{a}” contains an acid: we found no age guidance for children under {n}, ask a doctor first.',
  '«{a}» содержит ретиноид: используйте вечером, а каждое утро наносите солнцезащитное средство SPF 30+. При беременности и её планировании ретиноиды не используют: спросите врача.':
      '“{a}” contains a retinoid: use it in the evening and apply SPF 30+ sunscreen every morning. Retinoids are not used during pregnancy or when planning one: ask a doctor.',
  '«{a}» содержит кислоту: каждое утро наносите солнцезащитное средство SPF 30+, не наслаивайте несколько кислот сразу.':
      '“{a}” contains an acid: apply SPF 30+ sunscreen every morning and do not layer several acids at once.',
  '«{a}» содержит бензоилпероксид: он может раздражать кожу. Перед первым использованием 3 дня проверьте его на небольшом участке кожи.':
      '“{a}” contains benzoyl peroxide: it can irritate the skin. Test it on a small area of skin for 3 days before the first use.',
  'Сразу {n} средств для ухода при чувствительной коже: если одно не подойдёт, реакцию трудно связать с конкретным. Начните с базового крема, 3 дня пробуйте его на небольшом участке кожи (за ухом или на запястье), остальное добавляйте по одному.':
      '{n} care products at once on sensitive skin: if one does not suit you, it is hard to tell which one caused the reaction. Start with a basic cream, test it on a small area of skin (behind the ear or on the wrist) for 3 days, and add the rest one at a time.',
  '«{a}» содержит активные компоненты: при чувствительной коже сначала на 3 дня нанесите на небольшой участок кожи.':
      '“{a}” contains active ingredients: on sensitive skin, first apply it to a small area of skin for 3 days.',
  '«{a}» содержит ретиноид: используйте вечером, а каждое утро наносите солнцезащитное средство SPF 30+. При беременности и её планировании ретиноиды не используют: спросите врача. Сначала на 3 дня нанесите на небольшой участок кожи.':
      '“{a}” contains a retinoid: use it in the evening and apply SPF 30+ sunscreen every morning. Retinoids are not used during pregnancy or when planning one: ask a doctor. First apply it to a small area of skin for 3 days.',
  '«{a}» содержит кислоту: каждое утро наносите солнцезащитное средство SPF 30+, не наслаивайте несколько кислот сразу. Сначала на 3 дня нанесите на небольшой участок кожи.':
      '“{a}” contains an acid: apply SPF 30+ sunscreen every morning and do not layer several acids at once. First apply it to a small area of skin for 3 days.',
  'LHA (каприлоил салициловая кислота)': 'LHA (capryloyl salicylic acid)',
  'Производные витамина C': 'Vitamin C derivatives',
  'Нужен для безопасности: детям до 12 лет не предлагают ретиноиды и бензоилпероксид.':
      'Used for safety: children under 12 are not offered retinoids and benzoyl peroxide.',
  'Скрыто по возрасту: {n}. Ретиноиды и бензоилпероксид детям до 12 лет не предлагают.':
      'Hidden because of age: {n}. Retinoids and benzoyl peroxide are not offered to children under 12.',
  'Без ароматических аллергенов (список ЕС)':
      'Free of fragrance allergens (EU list)',
  'Ароматические аллергены (список ЕС): {v0}':
      'Fragrance allergens (EU list): {v0}',
  'ЕС требует называть эти вещества в составе: они вызывали аллергию у людей. Если кожа склонна к реакциям, сначала проверьте средство на небольшом участке.':
      'The EU requires these substances to be named in the ingredients: they have caused allergies in people. If your skin is prone to reactions, test the product on a small area first.',
  'Интенсивность: {v0}%': 'Intensity: {v0}%',
  'Свой цвет': 'Custom colour',
  'Оттенок': 'Hue',
  'Насыщенность': 'Saturation',
  'Яркость': 'Lightness',
  'Виртуальная примерка: приблизительный результат, а не гарантия реального макияжа. Кожа не ретушируется: поры, прыщи, рубцы и покраснения остаются.':
      'Virtual try-on: an approximate result, not a guarantee of real makeup. The skin is not retouched: pores, acne, scars and redness stay.',
  'Розовый': 'Pink',
  'Нюд': 'Nude',
  'Мальва': 'Mauve',
  'Серо-синий': 'Grey-blue',
  'Шалфей': 'Sage',
  'Дымчатый': 'Smoky',
  'Терракотовый': 'Terracotta',
  'Нежный': 'Soft',
  'Помада': 'Lipstick',
  'Тени': 'Eyeshadow',
  'Закрасьте участки, которые должны остаться как на фото: прыщи, рубцы, покраснения, родинки. Здесь макияж не применяется вообще.':
      'Paint over the areas that must stay as in the photo: acne, scars, redness, moles. No makeup is applied there at all.',
  'Кисть': 'Brush',
  'Ластик': 'Eraser',
  'Размер кисти': 'Brush size',
  'Вернуть': 'Redo',
  'Защищено: {v0}% фото': 'Protected: {v0}% of the photo',
  'Подсказка находит только мелкие красные или тёмные пятна и может ошибаться: проверьте и поправьте вручную.':
      'The hint finds only small red or dark spots and can be wrong: check it and correct it by hand.',
  'Подсказать участки': 'Suggest areas',
  'Слишком много участков выделилось (свет или косметика). Подсказка не показана, отметьте участки вручную.':
      'Too many areas were marked (light or cosmetics). The hint is not shown, mark the areas by hand.',
  'Мелких пятен не найдено. Это не значит, что их нет: отметьте нужные участки вручную.':
      'No small spots were found. That does not mean there are none: mark the areas you need by hand.',
  'Найдено участков: {v0}. Проверьте их на фото (жёлтые).':
      'Areas found: {v0}. Check them on the photo (yellow).',
  'Защитить': 'Protect',
  'Отклонить': 'Dismiss',
  'Не удалось открыть фото': 'Could not open the photo',
  'Виртуальная примерка': 'Virtual try-on',
  'Ищем лицо…': 'Looking for the face…',
  'Лицо не найдено. Выберите фото, где лицо хорошо видно и смотрит в камеру.':
      'No face found. Choose a photo where the face is clearly visible and looks at the camera.',
  'На фото несколько лиц. Выберите фото с одним лицом: иначе примерка была бы догадкой.':
      'There are several faces in the photo. Choose a photo with one face: otherwise the try-on would be a guess.',
  'Не удалось обработать фото. Попробуйте другое.':
      'Could not process the photo. Try another one.',
  'Оригинал': 'Original',
  'Разделитель': 'Slider',
  'Удерживайте фото, чтобы увидеть оригинал.':
      'Hold the photo to see the original.',
  'Защита кожи': 'Skin protection',
  'Другое фото': 'Another photo',
  'Голова повёрнута: губы, веки и румяна могут лечь неточно.':
      'The head is turned: lips, eyelids and blush may be placed less precisely.',
  'Голова наклонена: зоны могут лечь неточно.':
      'The head is tilted: the zones may be placed less precisely.',
  'Лицо на фото маленькое: зоны состоят из малого числа точек, результат грубее.':
      'The face in the photo is small: the zones are made of few pixels, the result is rougher.',
  'На фото несколько лиц.': 'There are several faces in the photo.',
  'Примерьте макияж на своё фото': 'Try makeup on your own photo',
  'Фото обрабатывается на телефоне: оно не отправляется на сервер и не сохраняется.':
      'The photo is processed on the phone: it is not sent to a server and not saved.',
  'Выбрать фото': 'Choose a photo',
  'Цвет по данным производителя': 'Colour from the manufacturer\'s data',
  'Цвет измерен по образцу производителя, приблизительно':
      'Colour measured on the manufacturer\'s swatch, approximate',
  'Цвет оценён по фото товара, не по данным производителя':
      'Colour estimated from the product photo, not the manufacturer\'s data',
  'Цвет оттенка приблизительный: он зависит от освещения на фото, экрана и свойств косметики. Реальный продукт может выглядеть иначе.':
      'The shade colour is approximate: it depends on the light in the photo, the screen and the properties of the cosmetic. The real product may look different.',
  'Другие оттенки линейки': 'Other shades of the line',
  'Подбор по виду макияжа': 'Choose by kind of makeup',
  'Для этого вида в каталоге пока нет товаров с известным цветом. Выберите «Свой цвет».':
      'There are no products with a known colour for this kind in the catalog yet. Choose “Custom colour”.',
  'К карточке товара': 'To the product page',
  'Покрытие: {v0}': 'Finish: {v0}',
  'матовое': 'matte',
  'сатиновое': 'satin',
  'глянцевое': 'glossy',
  'с шиммером': 'with shimmer',
  'Примерить': 'Try on',
  'Примерка недоступна: в каталоге нет данных о цвете этого оттенка.':
      'Try-on is not available: the catalog has no colour data for this shade.',
};
