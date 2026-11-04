/// The only app events that may be sent to the server. The list is deliberately
/// short and is a PROPOSAL until the data-collection rules are approved: adding
/// a type, or a property to one, is a change of those rules (raise
/// `ServerConsent.currentVersion` with it so the user is asked again).
///
/// Never in an event: search texts, names, photos, skin or face analysis
/// results, notes, anything typed by the user.
enum AppEventType {
  /// The app was opened. Counts as a "sign-in" in the admin panel.
  appOpen('app_open'),

  /// A screen was shown. Property: `screen`, a fixed snake_case name from the
  /// app's own list of screens (never a title or a user text).
  screenView('screen_view'),

  /// A product page was opened. Property: `productId`.
  productView('product_view'),

  /// A product was added to / removed from favourites. Properties: `productId`,
  /// `favorited`.
  productFavorited('product_favorited');

  const AppEventType(this.wire);

  /// The name the server stores.
  final String wire;
}

/// One event, built only through the constructors below: they carry exactly the
/// properties allowed for the type, so a free-form value cannot slip in.
class AppEvent {
  const AppEvent._(this.type, this.props, this.time);

  final AppEventType type;
  final Map<String, Object> props;

  /// The device clock (informational; the server stamps its own time too).
  final DateTime time;

  static DateTime _now(DateTime? t) => (t ?? DateTime.now()).toUtc();

  factory AppEvent.appOpen({DateTime? at}) =>
      AppEvent._(AppEventType.appOpen, const {}, _now(at));

  /// [screen] is a fixed internal name like `catalog` or `product_page`.
  factory AppEvent.screenView(String screen, {DateTime? at}) {
    if (!_screenName.hasMatch(screen)) {
      throw ArgumentError.value(
        screen,
        'screen',
        'must be a snake_case screen name (a-z, 0-9, _), up to 40 characters',
      );
    }
    return AppEvent._(AppEventType.screenView, {'screen': screen}, _now(at));
  }

  factory AppEvent.productView(int productId, {DateTime? at}) {
    _checkId(productId);
    return AppEvent._(AppEventType.productView, {
      'productId': productId,
    }, _now(at));
  }

  factory AppEvent.productFavorited(
    int productId, {
    required bool favorited,
    DateTime? at,
  }) {
    _checkId(productId);
    return AppEvent._(AppEventType.productFavorited, {
      'productId': productId,
      'favorited': favorited,
    }, _now(at));
  }

  static final _screenName = RegExp(r'^[a-z][a-z0-9_]{0,39}$');

  static void _checkId(int id) {
    if (id < 1) throw ArgumentError.value(id, 'productId', 'must be positive');
  }

  Map<String, Object?> toJson() => {
    'type': type.wire,
    if (props.isNotEmpty) 'props': props,
    'clientTime': time.toIso8601String(),
  };
}
