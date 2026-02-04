import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../product/domain/app_product.dart';
import '../../product/state/products_providers.dart';
import '../../../core/widgets/product_card.dart';

enum _SellerFilter { all, available, sold }

enum _SellerSort { newest, oldest, priceLow, priceHigh }

class SellerProductsScreen extends ConsumerStatefulWidget {
  const SellerProductsScreen({
    super.key,
    required this.sellerId,
    this.sellerName,
  });

  final String sellerId;
  final String? sellerName;

  @override
  ConsumerState<SellerProductsScreen> createState() => _SellerProductsScreenState();
}

class _SellerProductsScreenState extends ConsumerState<SellerProductsScreen> {
  _SellerFilter _filter = _SellerFilter.all;
  _SellerSort _sort = _SellerSort.newest;

  String _tr(BuildContext context, {required String ar, required String fr, required String en}) {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    if (code == 'ar') return ar;
    if (code == 'fr') return fr;
    return en;
  }

  int _colsFor(double w) {
    if (w >= 900) return 5;
    if (w >= 700) return 4;
    if (w >= 520) return 3;
    return 2;
  }

  double _aspectFor(int cols) {
    if (cols <= 2) return 0.95;
    if (cols == 3) return 0.86;
    return 0.78;
  }

  void _smartBack(BuildContext context) {
    final r = GoRouter.of(context);
    if (r.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  String _filterLabel(BuildContext context, _SellerFilter f) {
    switch (f) {
      case _SellerFilter.all:
        return _tr(context, ar: 'الكل', fr: 'Tous', en: 'All');
      case _SellerFilter.available:
        return _tr(context, ar: 'المتوفر', fr: 'Disponible', en: 'Available');
      case _SellerFilter.sold:
        return _tr(context, ar: 'المباع', fr: 'Vendu', en: 'Sold');
    }
  }

  String _sortLabel(BuildContext context, _SellerSort s) {
    switch (s) {
      case _SellerSort.newest:
        return _tr(context, ar: 'الأحدث', fr: 'Plus récent', en: 'Newest');
      case _SellerSort.oldest:
        return _tr(context, ar: 'الأقدم', fr: 'Plus ancien', en: 'Oldest');
      case _SellerSort.priceLow:
        return _tr(context, ar: 'السعر: الأقل', fr: 'Prix: bas', en: 'Price: low');
      case _SellerSort.priceHigh:
        return _tr(context, ar: 'السعر: الأعلى', fr: 'Prix: haut', en: 'Price: high');
    }
  }

  List<AppProduct> _buildItems(List<AppProduct> all) {
    Iterable<AppProduct> out = all;

    switch (_filter) {
      case _SellerFilter.all:
        break;
      case _SellerFilter.available:
        out = out.where((p) => !p.isSold);
        break;
      case _SellerFilter.sold:
        out = out.where((p) => p.isSold);
        break;
    }

    final items = out.toList(growable: false);

    int cmp(AppProduct a, AppProduct b) {
      switch (_sort) {
        case _SellerSort.newest:
          return b.publishedAt.compareTo(a.publishedAt);
        case _SellerSort.oldest:
          return a.publishedAt.compareTo(b.publishedAt);
        case _SellerSort.priceLow:
          return a.price.compareTo(b.price);
        case _SellerSort.priceHigh:
          return b.price.compareTo(a.price);
      }
    }

    items.sort(cmp);
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final name = (widget.sellerName ?? '').trim();
    final title = name.isNotEmpty
        ? name
        : _tr(context, ar: 'منتجات البائع', fr: 'Produits du vendeur', en: "Seller's products");

    final asyncItems = ref.watch(sellerProductsProvider(widget.sellerId.trim()));

    final w = MediaQuery.sizeOf(context).width;
    final cols = _colsFor(w);
    final aspect = _aspectFor(cols);

    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        leading: IconButton(
          tooltip: _tr(context, ar: 'رجوع', fr: 'Retour', en: 'Back'),
          icon: const BackButtonIcon(),
          onPressed: () => _smartBack(context),
        ),
      ),
      body: asyncItems.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Text(
              _tr(context, ar: 'تعذر تحميل منتجات البائع', fr: 'Erreur de chargement', en: 'Failed to load seller products'),
              style: TextStyle(color: cs.onSurface.withOpacity(0.7), fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (all) {
          final items = _buildItems(all);
          final allCount = all.length;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cs.outlineVariant.withAlpha(160)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _tr(context, ar: 'عدد المنتجات: $allCount', fr: 'Produits: $allCount', en: 'Products: $allCount'),
                              style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface.withAlpha(210)),
                            ),
                          ),
                          SizedBox(
                            width: 170,
                            child: DropdownButtonFormField<_SellerSort>(
                              value: _sort,
                              isDense: true,
                              decoration: InputDecoration(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              items: _SellerSort.values
                                  .map((s) => DropdownMenuItem(
                                        value: s,
                                        child: Text(
                                          _sortLabel(context, s),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
                                        ),
                                      ))
                                  .toList(growable: false),
                              onChanged: (v) {
                                if (v == null) return;
                                setState(() => _sort = v);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _SellerFilter.values.map((f) {
                          final selected = _filter == f;
                          return ChoiceChip(
                            selected: selected,
                            label: Text(
                              _filterLabel(context, f),
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: selected ? cs.onPrimary : cs.onSurface,
                              ),
                            ),
                            selectedColor: cs.primary,
                            onSelected: (_) => setState(() => _filter = f),
                          );
                        }).toList(growable: false),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Text(
                            _tr(context, ar: 'لا توجد منتجات هنا', fr: 'Aucun produit', en: 'No products here'),
                            style: TextStyle(color: cs.onSurface.withOpacity(0.7), fontWeight: FontWeight.w800),
                          ),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: aspect,
                        ),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final p = items[i];
                          return ProductCard(
                            product: p,
                            variant: ProductCardVariant.grid,
                            onTap: () => context.push('/product/${p.id}'),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
