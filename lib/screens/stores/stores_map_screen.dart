import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/providers/cart_provider.dart';
import 'package:cosmetix/providers/catalog_provider.dart';
import 'package:cosmetix/providers/location_provider.dart';
import 'package:cosmetix/providers/settings_provider.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/common_widgets.dart';
import 'package:cosmetix/widgets/custom_button.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';
import 'package:cosmetix/widgets/product_art.dart';

enum _Sort { nearest, cheapest }

/// Shops on a map with the distance from the user. Opened from a product it
/// also shows the price and the stock of that product in every shop.
///
/// Addresses, positions and opening hours are real (OpenStreetMap); prices and
/// stock are demo data until a shop provides a real feed (`product_prices.source`
/// is then not "demo" and the screen shows when it was updated).
class StoresMapScreen extends StatefulWidget {
  const StoresMapScreen({super.key, this.productId, this.showTiles});

  final int? productId;

  /// Map tiles come from the Internet; tests switch them off (see
  /// [defaultShowTiles]).
  final bool? showTiles;

  /// Used when [showTiles] is not given: false in widget tests.
  static bool defaultShowTiles = true;

  @override
  State<StoresMapScreen> createState() => _StoresMapScreenState();
}

class _StoresMapScreenState extends State<StoresMapScreen> {
  final _map = MapController();
  List<StoreInfo> _stores = [];
  final Map<int, StorePrice> _offers = {};
  bool _loading = true;
  String? _chain;
  bool _onlyInStock = false;
  _Sort _sort = _Sort.nearest;
  int? _selected;
  bool _centeredOnUser = false;

  /// The map fills the whole screen (a small map shows too little); the
  /// camera is kept when switching, so the same place stays in view.
  bool _full = false;
  LatLng? _camCenter;
  double? _camZoom;

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final loc = context.read<LocationProvider>();
      if (!loc.isReal) loc.refresh();
    });
  }

  Future<void> _load() async {
    final catalog = context.read<CatalogProvider>();
    try {
      final stores = await catalog.stores();
      final id = widget.productId;
      final offers = id == null
          ? const <StorePrice>[]
          : await catalog.storePrices(id);
      if (!mounted) return;
      setState(() {
        _stores = stores;
        _offers
          ..clear()
          ..addEntries(offers.map((o) => MapEntry(o.storeId, o)));
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The shops to list, after the filters, nearest/cheapest first.
  List<({StoreInfo store, StorePrice? offer, int meters})> _rows(
    LocationProvider loc,
  ) {
    final rows = [
      for (final s in _stores)
        if (_chain == null || s.chain == _chain)
          if (widget.productId == null || _offers.containsKey(s.id))
            if (!_onlyInStock || (_offers[s.id]?.inStock ?? true))
              (
                store: s,
                offer: _offers[s.id],
                meters: loc.distanceTo(s.lat, s.lng),
              ),
    ];
    rows.sort((a, b) {
      if (_sort == _Sort.cheapest && a.offer != null && b.offer != null) {
        // in-stock shops first, then by price
        if (a.offer!.inStock != b.offer!.inStock) {
          return a.offer!.inStock ? -1 : 1;
        }
        final byPrice = a.offer!.price.compareTo(b.offer!.price);
        if (byPrice != 0) return byPrice;
      }
      return a.meters.compareTo(b.meters);
    });
    return rows;
  }

  Color _pinColor(StorePrice? o) {
    if (o == null) return context.pal.accent;
    return switch (o.level) {
      StockLevel.inStock => AppColors.success,
      StockLevel.low => AppColors.warning,
      StockLevel.out => const Color(0xFF9A9A9A),
      StockLevel.unknown => context.pal.accent,
    };
  }

  void _select(StoreInfo s) {
    setState(() => _selected = s.id);
    _map.move(LatLng(s.lat, s.lng), 14.5);
  }

  Future<void> _addToCart(Product product, StorePrice offer) async {
    final err = await context.read<CartProvider>().add(
      product,
      storeId: offer.storeId,
    );
    if (!mounted) return;
    showMessage(
      context,
      err ?? trf('Добавлено в корзину: {v0}', {'v0': tr(offer.storeName)}),
      type: err == null ? MessageType.success : MessageType.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocationProvider>();
    final catalog = context.watch<CatalogProvider>();
    final product = widget.productId == null
        ? null
        : catalog.byId(widget.productId!);
    final pal = context.pal;
    final rows = _rows(loc);
    final chains = {for (final s in _stores) s.chain}.toList()..sort();
    final origin = LatLng(loc.origin.lat, loc.origin.lng);
    if (loc.isReal && !_centeredOnUser && _selected == null) {
      // the position arrived after the map was shown: go to the user
      _centeredOnUser = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _map.move(origin, 13.5);
        } catch (_) {
          // the map is not on screen (tests): nothing to move
        }
      });
    }

    if (_full) return _fullScreen(origin, rows, loc, product);

    return PageScaffold(
      title: product == null ? tr('Магазины рядом') : tr('Где купить'),
      bigTitle: true,
      showNav: false,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                if (product != null) _ProductHeader(product: product),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    height: 230,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _mapBody(origin, rows, loc),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: _MapButton(
                              icon: Icons.fullscreen,
                              tooltip: tr('Карта на весь экран'),
                              onTap: () => setState(() => _full = true),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      AppChip(
                        label: tr('Все'),
                        selected: _chain == null,
                        onTap: () => setState(() => _chain = null),
                      ),
                      for (final c in chains) ...[
                        const SizedBox(width: 8),
                        AppChip(
                          label: tr(c),
                          selected: _chain == c,
                          onTap: () => setState(() => _chain = c),
                        ),
                      ],
                    ],
                  ),
                ),
                if (product != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        AppChip(
                          label: tr('Ближе ко мне'),
                          selected: _sort == _Sort.nearest,
                          onTap: () => setState(() => _sort = _Sort.nearest),
                        ),
                        AppChip(
                          label: tr('Сначала дешёвые'),
                          selected: _sort == _Sort.cheapest,
                          onTap: () => setState(() => _sort = _Sort.cheapest),
                        ),
                        AppChip(
                          label: tr('В наличии'),
                          selected: _onlyInStock,
                          onTap: () =>
                              setState(() => _onlyInStock = !_onlyInStock),
                        ),
                      ],
                    ),
                  ),
                _notes(loc, pal),
                if (rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: EmptyState(
                      icon: Icons.storefront_outlined,
                      title: tr('Нет подходящих магазинов'),
                      subtitle: tr('Измените фильтры'),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Column(
                      children: [
                        for (final r in rows)
                          _StoreCard(
                            store: r.store,
                            offer: r.offer,
                            meters: r.meters,
                            selected: _selected == r.store.id,
                            product: product,
                            onTap: () => _select(r.store),
                            onAdd: product == null || r.offer == null
                                ? null
                                : () => _addToCart(product, r.offer!),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _mapBody(
    LatLng origin,
    List<({StoreInfo store, StorePrice? offer, int meters})> rows,
    LocationProvider loc,
  ) => (widget.showTiles ?? StoresMapScreen.defaultShowTiles)
      ? _mapView(origin, rows, loc)
      : Container(
          color: context.pal.pinkSoft,
          alignment: Alignment.center,
          child: Text(tr('Карта')),
        );

  /// The map over the whole screen: pins, a button for "where am I", and the
  /// card of the shop you tapped at the bottom.
  Widget _fullScreen(
    LatLng origin,
    List<({StoreInfo store, StorePrice? offer, int meters})> rows,
    LocationProvider loc,
    Product? product,
  ) {
    final picked = rows.where((r) => r.store.id == _selected).firstOrNull;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _full = false);
      },
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(child: _mapBody(origin, rows, loc)),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: _MapButton(
                    icon: Icons.fullscreen_exit,
                    tooltip: tr('Свернуть карту'),
                    onTap: () => setState(() => _full = false),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Align(
                  alignment: Alignment.topRight,
                  child: _MapButton(
                    icon: Icons.my_location,
                    tooltip: tr('Моё положение'),
                    onTap: () {
                      try {
                        _map.move(origin, 14);
                      } catch (_) {
                        // the map is not on screen (tests)
                      }
                    },
                  ),
                ),
              ),
            ),
            if (picked != null)
              Positioned(
                left: 12,
                right: 12,
                bottom: 0,
                child: SafeArea(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                    ),
                    child: SingleChildScrollView(
                      child: _StoreCard(
                        store: picked.store,
                        offer: picked.offer,
                        meters: picked.meters,
                        selected: true,
                        product: product,
                        onTap: () {},
                        onAdd: product == null || picked.offer == null
                            ? null
                            : () => _addToCart(product, picked.offer!),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _mapView(
    LatLng origin,
    List<({StoreInfo store, StorePrice? offer, int meters})> rows,
    LocationProvider loc,
  ) {
    return FlutterMap(
      key: ValueKey(_full),
      mapController: _map,
      options: MapOptions(
        initialCenter: _camCenter ?? origin,
        initialZoom: _camZoom ?? 12,
        minZoom: 9,
        maxZoom: 18,
        onPositionChanged: (camera, _) {
          _camCenter = camera.center;
          _camZoom = camera.zoom;
        },
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'kz.cosmetix.cosmetix',
        ),
        MarkerLayer(
          markers: [
            for (final r in rows)
              Marker(
                point: LatLng(r.store.lat, r.store.lng),
                width: 42,
                height: 42,
                child: GestureDetector(
                  onTap: () => _select(r.store),
                  child: _Pin(
                    color: _pinColor(r.offer),
                    selected: _selected == r.store.id,
                    label: r.store.chain.isEmpty
                        ? '•'
                        : r.store.chain.characters.first.toUpperCase(),
                  ),
                ),
              ),
            if (loc.isReal)
              Marker(
                point: origin,
                width: 22,
                height: 22,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF2F7DF6),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                ),
              ),
          ],
        ),
        // the OpenStreetMap licence asks for a visible credit
        const Align(
          alignment: Alignment.bottomRight,
          child: ColoredBox(
            color: Color(0xCCFFFFFF),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              child: Text(
                '© OpenStreetMap contributors',
                style: TextStyle(fontSize: 9, color: Color(0xFF444444)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _notes(LocationProvider loc, AppPalette pal) {
    final demo = _offers.values.any((o) => o.demo);
    final lines = <Widget>[
      if (loc.loading)
        _note(Icons.my_location, tr('Определяем ваше положение…'), pal)
      else if (loc.isReal)
        _note(
          Icons.my_location,
          tr('Расстояния считаются от вашего положения'),
          pal,
        )
      else
        _note(
          Icons.location_off_outlined,
          tr('Геолокация недоступна: расстояния считаются от центра Астаны'),
          pal,
          action: TextButton(
            onPressed: context.read<LocationProvider>().refresh,
            child: Text(tr('Разрешить')),
          ),
        ),
      if (widget.productId != null && demo)
        _note(
          Icons.info_outline,
          tr(
            'Адреса и часы работы настоящие, а цены и наличие демонстрационные: у магазинов нет открытых данных. Перед визитом уточните по телефону.',
          ),
          pal,
        ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Column(children: lines),
    );
  }

  Widget _note(IconData icon, String text, AppPalette pal, {Widget? action}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: pal.subtext),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.caption.copyWith(color: pal.subtext),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// Round button on top of the map (expand, collapse, my position).
class _MapButton extends StatelessWidget {
  const _MapButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    elevation: 3,
    shape: const CircleBorder(),
    child: IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, color: const Color(0xFF3A3135)),
    ),
  );
}

class _Pin extends StatelessWidget {
  const _Pin({
    required this.color,
    required this.selected,
    required this.label,
  });

  final Color color;
  final bool selected;
  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: selected ? 38 : 30,
      height: selected ? 38 : 30,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: selected ? 3 : 2),
        boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
    ),
  );
}

class _ProductHeader extends StatelessWidget {
  const _ProductHeader({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: AppCard(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: ProductArt(
                art: product.art,
                color: product.color,
                radius: 8,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.brand,
                    style: TextStyle(fontSize: 10, color: pal.subtext),
                  ),
                  Text(
                    tr(product.name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyBold,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoreCard extends StatelessWidget {
  const _StoreCard({
    required this.store,
    required this.offer,
    required this.meters,
    required this.selected,
    required this.product,
    required this.onTap,
    required this.onAdd,
  });

  final StoreInfo store;
  final StorePrice? offer;
  final int meters;
  final bool selected;
  final Product? product;
  final VoidCallback onTap;
  final VoidCallback? onAdd;

  String get _distance => meters >= 1000
      ? trf('{v0} км', {
          'v0': (meters / 1000).toStringAsFixed(1).replaceAll('.', ','),
        })
      : trf('{v0} м', {'v0': meters});

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final fmt = context.watch<SettingsProvider>().priceText;
    final status = openStatusOf(store.hours, DateTime.now());
    final o = offer;
    final (chipColor, chipBg, chipText) = switch (o?.level) {
      StockLevel.inStock => (
        AppColors.success,
        context.pal.greenSoft,
        o!.qty == null
            ? tr('В наличии')
            : trf('В наличии · {v0} шт.', {'v0': o.qty}),
      ),
      StockLevel.low => (
        const Color(0xFF9A6A12),
        const Color(0xFFFBF0D9),
        trf('Мало · {v0} шт.', {'v0': o!.qty}),
      ),
      StockLevel.unknown => (
        context.pal.subtext,
        context.pal.field,
        tr('Наличие не проверено'),
      ),
      StockLevel.out => (
        AppColors.sale,
        context.pal.redSoft,
        tr('Нет в наличии'),
      ),
      null => (context.pal.accent, context.pal.pinkSoft, ''),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        onTap: onTap,
        borderColor: selected ? AppColors.primaryDark : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(tr(store.name), style: AppTextStyles.subtitle),
                ),
                if (o != null)
                  Text(
                    fmt(o.price),
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: o.inStock ? pal.text : pal.subtext,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.place, size: 14, color: context.pal.accent),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    tr(store.address),
                    style: AppTextStyles.caption.copyWith(color: pal.subtext),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              [
                trf('{v0} от вас', {'v0': _distance}),
                if (status.isNotEmpty) status,
              ].join(' • '),
              style: AppTextStyles.caption.copyWith(color: pal.subtext),
            ),
            if (o != null) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: chipBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      chipText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: chipColor,
                      ),
                    ),
                  ),
                  if (o.demo)
                    Text(
                      tr('демо-данные'),
                      style: AppTextStyles.caption.copyWith(color: pal.subtext),
                    )
                  else if (o.updatedAt != null)
                    Text(
                      trf('обновлено {v0}', {
                        'v0': _stamp(
                          DateTime.fromMillisecondsSinceEpoch(o.updatedAt!),
                        ),
                      }),
                      style: AppTextStyles.caption.copyWith(color: pal.subtext),
                    ),
                ],
              ),
            ],
            if (selected && onAdd != null && (o?.inStock ?? false)) ...[
              const SizedBox(height: 10),
              CustomButton(
                label: tr('Добавить в корзину из этого магазина'),
                onPressed: onAdd,
              ),
            ],
            if (selected && store.source.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                trf('Адрес: {v0}', {'v0': tr(store.source)}),
                style: AppTextStyles.caption.copyWith(color: pal.subtext),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _stamp(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
