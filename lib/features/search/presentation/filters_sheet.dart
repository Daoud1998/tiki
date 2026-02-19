import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/data/ma_catalog.dart';
import '../../../core/data/ma_neighborhood_suggestions.dart';
import '../../../core/data/ma_suggestions.dart';

enum SearchSort { newest, priceLow, priceHigh, oldest }

@immutable
class SearchFilters {
  const SearchFilters({
    this.wilayaId,
    this.moughataaId,
    this.neighborhoodId,
    this.neighborhood,
    this.minPrice,
    this.maxPrice,
    this.categoryId,
    this.subCategoryId,
    this.sort = SearchSort.newest,
  });

  final String? wilayaId;
  final String? moughataaId;
  final String? neighborhood;
  final String? neighborhoodId;
  final int? minPrice;
  final int? maxPrice;
  final String? categoryId;
  final String? subCategoryId;
  final SearchSort sort;

  SearchFilters copyWith({
    String? wilayaId,
    String? moughataaId,
    String? neighborhoodId,
    String? neighborhood,
    int? minPrice,
    int? maxPrice,
    String? categoryId,
    String? subCategoryId,
    SearchSort? sort,
  }) {
    return SearchFilters(
      wilayaId: wilayaId ?? this.wilayaId,
      moughataaId: moughataaId ?? this.moughataaId,
      neighborhoodId: neighborhoodId ?? this.neighborhoodId,
      neighborhood: neighborhood ?? this.neighborhood,
      minPrice: minPrice ?? this.minPrice,
      maxPrice: maxPrice ?? this.maxPrice,
      categoryId: categoryId ?? this.categoryId,
      subCategoryId: subCategoryId ?? this.subCategoryId,
      sort: sort ?? this.sort,
    );
  }

  SearchFilters cleared() => const SearchFilters();
}

Future<SearchFilters?> showSearchFiltersSheet(
  BuildContext context, {
  required SearchFilters initial,
  int? maxPriceHint,
}) {
  return showModalBottomSheet<SearchFilters>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => _FiltersSheet(
      initial: initial,
      maxPriceHint: maxPriceHint,
    ),
  );
}

class _FiltersSheet extends StatefulWidget {
  const _FiltersSheet({required this.initial, this.maxPriceHint});
  final SearchFilters initial;
  final int? maxPriceHint;

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late String? wilayaId = widget.initial.wilayaId;
  late String? moughataaId = widget.initial.moughataaId;
  late String? neighborhoodId = widget.initial.neighborhoodId;
  final _neighborhoodCtrl = TextEditingController();
  late String? categoryId = widget.initial.categoryId;
  late String? subCategoryId = widget.initial.subCategoryId;
  late SearchSort sort = widget.initial.sort;

  final _minCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();

  late double _minRange;
  late double _maxRange;
  late double _rangeMax;

  @override
  void initState() {
    super.initState();
    _neighborhoodCtrl.text = (widget.initial.neighborhood ?? '').toString();
    _minCtrl.text = widget.initial.minPrice?.toString() ?? '';
    _maxCtrl.text = widget.initial.maxPrice?.toString() ?? '';

    const hardMax = 10000000;
    // Slider upper bound is fixed to 10,000,000 MRU.
    _rangeMax = hardMax.toDouble();

    final initMin = (widget.initial.minPrice ?? 0).clamp(0, _rangeMax.toInt());
    final initMax = (widget.initial.maxPrice ?? _rangeMax.toInt())
        .clamp(0, _rangeMax.toInt());
    final fixed = _fixMinMax(initMin, initMax);
    _minRange = fixed.$1.toDouble();
    _maxRange = fixed.$2.toDouble();
  }

  @override
  void dispose() {
    _neighborhoodCtrl.dispose();
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final isAr = locale.languageCode.toLowerCase() == 'ar';
    final cs = Theme.of(context).colorScheme;

    final selectedWilaya = wilayaId == null ? null : findWilayaById(wilayaId!);
    final moughataas = selectedWilaya?.moughataas ?? const <Moughataa>[];

    final selectedCategory =
        categoryId == null ? null : findCategoryById(categoryId!);
    final subs = selectedCategory == null
        ? const <SubCategory>[]
        : withOtherSubcategory(selectedCategory.sub);

    final title = _tr(context, ar: 'فلترة', fr: 'Filtres', en: 'Filters');
    final apply = _tr(context, ar: 'تطبيق', fr: 'Appliquer', en: 'Apply');
    final clear = _tr(context, ar: 'مسح', fr: 'Effacer', en: 'Clear');
    final priceLabel = _tr(
      context,
      ar: 'السعر (MRU)',
      fr: 'Prix (MRU)',
      en: 'Price (MRU)',
    );

    final insets = MediaQuery.viewInsetsOf(context);

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsetsDirectional.fromSTEB(
        16,
        8,
        16,
        insets.bottom + 16,
      ),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w900)),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    setState(() {
                      wilayaId = null;
                      moughataaId = null;
                      neighborhoodId = null;
                      _neighborhoodCtrl.text = '';
                      categoryId = null;
                      subCategoryId = null;
                      sort = SearchSort.newest;
                      _minCtrl.text = '';
                      _maxCtrl.text = '';
                      _minRange = 0;
                      _maxRange = _rangeMax;
                    });
                  },
                  child: Text(clear),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Active filter chips (quick remove)
            _ActiveChips(
              wilayaId: wilayaId,
              moughataaId: moughataaId,
              neighborhood: _neighborhoodCtrl.text.trim().isEmpty
                  ? null
                  : _neighborhoodCtrl.text.trim(),
              categoryId: categoryId,
              subCategoryId: subCategoryId,
              sort: sort,
              minPrice: _parsedInt(_minCtrl.text),
              maxPrice: _parsedInt(_maxCtrl.text),
              onClear: (kind) {
                setState(() {
                  switch (kind) {
                    case _ChipKind.wilaya:
                      wilayaId = null;
                      moughataaId = null;
                      break;
                    case _ChipKind.moughataa:
                      moughataaId = null;
                      neighborhoodId = null;
                      _neighborhoodCtrl.text = '';
                      break;
                    case _ChipKind.neighborhood:
                      neighborhoodId = null;
                      _neighborhoodCtrl.text = '';
                      break;
                    case _ChipKind.category:
                      categoryId = null;
                      subCategoryId = null;
                      break;
                    case _ChipKind.sub:
                      subCategoryId = null;
                      break;
                    case _ChipKind.sort:
                      sort = SearchSort.newest;
                      break;
                    case _ChipKind.price:
                      _minCtrl.text = '';
                      _maxCtrl.text = '';
                      _minRange = 0;
                      _maxRange = _rangeMax;
                      break;
                  }
                });
              },
            ),
            const SizedBox(height: 12),

            // 1) Location (Wilaya -> Moughataa)
            _SectionLabel(
                text: _tr(context, ar: 'المكان', fr: 'Lieu', en: 'Location')),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: wilayaId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText:
                    _tr(context, ar: 'الولاية', fr: 'Wilaya', en: 'Wilaya'),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text(_tr(context, ar: 'الكل', fr: 'Tous', en: 'All')),
                ),
                ...maWilayas.map(
                  (w) => DropdownMenuItem(
                    value: w.id,
                    child: Text(w.name.ofLocale(locale)),
                  ),
                ),
              ],
              onChanged: (v) {
                setState(() {
                  wilayaId = v;
                  moughataaId = null; // reset
                  neighborhoodId = null;
                  _neighborhoodCtrl.text = '';
                });
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: moughataaId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: _tr(context,
                    ar: 'المقاطعة', fr: 'Moughataa', en: 'Moughataa'),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text(_tr(context, ar: 'الكل', fr: 'Tous', en: 'All')),
                ),
                ...moughataas.map(
                  (m) => DropdownMenuItem(
                    value: m.id,
                    child: Text(m.name.ofLocale(locale)),
                  ),
                ),
              ],
              onChanged: (v) {
                setState(() {
                  moughataaId = v;
                  neighborhoodId = null;
                  _neighborhoodCtrl.text = '';
                });
              },
            ),

            const SizedBox(height: 10),
            // Neighborhood (Nouakchott + Nouadhibou)
            Builder(builder: (context) {
              final wId = (wilayaId ?? '').trim();
              final mId = (moughataaId ?? '').trim();
              final showNeighborhood =
                  wId.startsWith('nouakchott_') || wId == 'dakhlet_nouadhibou';

              if (!showNeighborhood) return const SizedBox.shrink();

              final label = _tr(context,
                  ar: 'الحي/المنطقة', fr: 'Quartier', en: 'Neighborhood');
              final hint = (mId.isEmpty)
                  ? _tr(context,
                      ar: 'اختر المقاطعة أولاً',
                      fr: 'Choisissez d’abord la moughataa',
                      en: 'Choose moughataa first')
                  : _tr(context,
                      ar: 'اختر من القائمة أو اكتب يدوياً',
                      fr: 'Choisissez ou saisissez',
                      en: 'Pick or type');

              return TextFormField(
                controller: _neighborhoodCtrl,
                readOnly: true,
                onTap: () async {
                  if (mId.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(_tr(context,
                            ar: 'اختر المقاطعة أولاً',
                            fr: 'Choisissez d’abord la moughataa',
                            en: 'Choose moughataa first')),
                        duration: const Duration(milliseconds: 1200),
                      ),
                    );
                    return;
                  }
                  await _pickNeighborhood(context);
                },
                decoration: InputDecoration(
                  labelText: label,
                  hintText: hint,
                  prefixIcon: const Icon(Icons.home_work_outlined),
                  suffixIcon: _neighborhoodCtrl.text.trim().isEmpty
                      ? const Icon(Icons.keyboard_arrow_down_rounded)
                      : IconButton(
                          tooltip: _tr(context,
                              ar: 'مسح', fr: 'Effacer', en: 'Clear'),
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            setState(() {
                              neighborhoodId = null;
                              _neighborhoodCtrl.text = '';
                            });
                          },
                        ),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              );
            }),

            const SizedBox(height: 16),

            // 2) Price (modern range slider + optional exact numbers)
            _SectionLabel(text: priceLabel),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant.withOpacity(0.55)),
              ),
              child: Column(
                children: [
                  // Price direction: Arabic shows min on the RIGHT (RTL); others LTR.
                  Directionality(
                    textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Text(
                              _fmtPrice(_minRange.toInt()),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900),
                            ),
                            const Spacer(),
                            Text(
                              _fmtPrice(_maxRange.toInt()),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ],
                        ),
                        RangeSlider(
                          values: RangeValues(_minRange, _maxRange),
                          min: 0,
                          max: _rangeMax,
                          divisions: 100,
                          labels: RangeLabels(
                            _fmtPrice(_minRange.toInt()),
                            _fmtPrice(_maxRange.toInt()),
                          ),
                          onChanged: (v) {
                            setState(() {
                              _minRange = v.start;
                              _maxRange = v.end;
                              _minCtrl.text = _minRange <= 0
                                  ? ''
                                  : _minRange.toInt().toString();
                              _maxCtrl.text = _maxRange >= _rangeMax
                                  ? ''
                                  : _maxRange.toInt().toString();
                            });
                          },
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Directionality(
                                // Keep labels RTL for Arabic, but numeric input stays LTR.
                                textDirection: Directionality.of(context),
                                child: TextField(
                                  controller: _minCtrl,
                                  keyboardType: TextInputType.number,
                                  textDirection: TextDirection.ltr,
                                  textAlign: TextAlign.center,
                                  decoration: InputDecoration(
                                    labelText: _tr(context,
                                        ar: 'أدنى', fr: 'Min', en: 'Min'),
                                    prefixIcon:
                                        const Icon(Icons.payments_outlined),
                                    suffixText: 'MRU',
                                    suffixStyle: TextStyle(
                                      color: cs.onSurface.withOpacity(0.65),
                                      fontWeight: FontWeight.w800,
                                    ),
                                    filled: true,
                                    fillColor: cs.surfaceContainerHighest
                                        .withOpacity(0.25),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  onChanged: (_) => _syncRangeFromText(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Directionality(
                                textDirection: Directionality.of(context),
                                child: TextField(
                                  controller: _maxCtrl,
                                  keyboardType: TextInputType.number,
                                  textDirection: TextDirection.ltr,
                                  textAlign: TextAlign.center,
                                  decoration: InputDecoration(
                                    labelText: _tr(context,
                                        ar: 'أقصى', fr: 'Max', en: 'Max'),
                                    prefixIcon:
                                        const Icon(Icons.payments_outlined),
                                    suffixText: 'MRU',
                                    suffixStyle: TextStyle(
                                      color: cs.onSurface.withOpacity(0.65),
                                      fontWeight: FontWeight.w800,
                                    ),
                                    filled: true,
                                    fillColor: cs.surfaceContainerHighest
                                        .withOpacity(0.25),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  onChanged: (_) => _syncRangeFromText(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (_hasMinMaxError())
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        _tr(context,
                            ar: 'ملاحظة: الحد الأدنى أكبر من الحد الأقصى.',
                            fr: 'Remarque: le min est > au max.',
                            en: 'Note: min is greater than max.'),
                        style: TextStyle(
                          color: cs.error,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 3) Sort (modern segmented)
            _SectionLabel(
                text: _tr(context, ar: 'الترتيب', fr: 'Tri', en: 'Sort')),
            const SizedBox(height: 8),
            _SortSegmented(
              value: sort,
              onChanged: (v) => setState(() => sort = v),
            ),

            const SizedBox(height: 16),

            // 4) Category -> subcategory
            _SectionLabel(
                text:
                    _tr(context, ar: 'الفئة', fr: 'Catégorie', en: 'Category')),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: categoryId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText:
                    _tr(context, ar: 'الفئة', fr: 'Catégorie', en: 'Category'),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text(_tr(context, ar: 'الكل', fr: 'Tous', en: 'All')),
                ),
                ...maCategories.map(
                  (c) => DropdownMenuItem(
                    value: c.id,
                    child: Text(c.name.ofLocale(locale)),
                  ),
                ),
              ],
              onChanged: (v) {
                setState(() {
                  categoryId = v;
                  subCategoryId = null;
                });
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: subCategoryId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: _tr(context,
                    ar: 'الفرعي', fr: 'Sous-catégorie', en: 'Subcategory'),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text(_tr(context, ar: 'الكل', fr: 'Tous', en: 'All')),
                ),
                ...subs.map(
                  (s) => DropdownMenuItem(
                    value: s.id,
                    child: Text(s.name.ofLocale(locale)),
                  ),
                ),
              ],
              onChanged: (v) => setState(() => subCategoryId = v),
            ),

            const SizedBox(height: 18),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  final minV = _parsedInt(_minCtrl.text);
                  final maxV = _parsedInt(_maxCtrl.text);

                  final fixed = _fixMinMax(minV ?? 0, maxV ?? 0);
                  final fixedMin = (minV == null) ? null : fixed.$1;
                  final fixedMax = (maxV == null) ? null : fixed.$2;
                  Navigator.pop(
                    context,
                    SearchFilters(
                      wilayaId: wilayaId,
                      moughataaId: moughataaId,
                      neighborhoodId: neighborhoodId,
                      neighborhood: _neighborhoodCtrl.text.trim().isEmpty
                          ? null
                          : _neighborhoodCtrl.text.trim(),
                      minPrice: fixedMin,
                      maxPrice: fixedMax,
                      categoryId: categoryId,
                      subCategoryId: subCategoryId,
                      sort: sort,
                    ),
                  );
                },
                child: Text(apply),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const String _kManualPick = '__manual__';

  Future<void> _pickNeighborhood(BuildContext context) async {
    final wId = (wilayaId ?? '').trim();
    final mId = (moughataaId ?? '').trim();
    if (wId.isEmpty || mId.isEmpty) return;

    final list = neighborhoodSuggestionsFor(wilayaId: wId, moughataaId: mId);
    final title =
        _tr(context, ar: 'الحي/المنطقة', fr: 'Quartier', en: 'Neighborhood');

    if (list.isEmpty) {
      await _openManualEntry(
        context,
        title: title,
        hint: _tr(context,
            ar: 'اكتب اسم الحي',
            fr: 'Saisissez le quartier',
            en: 'Type neighborhood'),
        initialValue: _neighborhoodCtrl.text.trim(),
        onSaved: (v) {
          setState(() {
            neighborhoodId = null;
            _neighborhoodCtrl.text = v.trim();
          });
        },
      );
      return;
    }

    final picked = await _openSuggestionPickerObj(
      context,
      title: title,
      suggestions: list,
      initialQuery: _neighborhoodCtrl.text.trim(),
    );
    if (!mounted || picked == null) return;

    if (picked is String && picked == _kManualPick) {
      await _openManualEntry(
        context,
        title: title,
        hint: _tr(context,
            ar: 'اكتب اسم الحي',
            fr: 'Saisissez le quartier',
            en: 'Type neighborhood'),
        initialValue: _neighborhoodCtrl.text.trim(),
        onSaved: (v) {
          setState(() {
            neighborhoodId = null;
            _neighborhoodCtrl.text = v.trim();
          });
        },
      );
      return;
    }

    if (picked is MaSuggestion) {
      setState(() {
        neighborhoodId = picked.id;
        _neighborhoodCtrl.text = picked.display(context);
      });
    }
  }

  Future<Object?> _openSuggestionPickerObj(
    BuildContext context, {
    required String title,
    required List<MaSuggestion> suggestions,
    String initialQuery = '',
  }) {
    final cs = Theme.of(context).colorScheme;
    final ctrl = TextEditingController(text: initialQuery);

    return showModalBottomSheet<Object?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        String query = initialQuery;
        List<MaSuggestion> filtered() {
          final q = query.trim();
          return suggestions.where((s) => s.matches(q)).toList(growable: false);
        }

        return StatefulBuilder(
          builder: (ctx, setModal) {
            final list = filtered();
            return Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                16,
                8,
                16,
                MediaQuery.viewInsetsOf(ctx).bottom + 12,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(title,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w900)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, _kManualPick),
                        child: Text(
                            _tr(ctx, ar: 'كتابة', fr: 'Saisir', en: 'Type')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: ctrl,
                    decoration: InputDecoration(
                      hintText: _tr(ctx,
                          ar: 'بحث…', fr: 'Rechercher…', en: 'Search…'),
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: cs.surfaceContainerHighest.withOpacity(0.35),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onChanged: (v) => setModal(() => query = v),
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: list.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: cs.outlineVariant.withOpacity(0.55),
                      ),
                      itemBuilder: (ctx, i) {
                        final s = list[i];
                        return ListTile(
                          dense: true,
                          title: Text(s.display(ctx)),
                          onTap: () => Navigator.pop(ctx, s),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(() => ctrl.dispose());
  }

  Future<void> _openManualEntry(
    BuildContext context, {
    required String title,
    required String hint,
    required String initialValue,
    required void Function(String value) onSaved,
  }) async {
    final cs = Theme.of(context).colorScheme;
    final ctrl = TextEditingController(text: initialValue);

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(hintText: hint),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(_tr(ctx, ar: 'إلغاء', fr: 'Annuler', en: 'Cancel')),
            ),
            FilledButton(
              onPressed: () {
                onSaved(ctrl.text);
                Navigator.pop(ctx);
              },
              child: Text(_tr(ctx, ar: 'حفظ', fr: 'OK', en: 'Save')),
            ),
          ],
        );
      },
    );

    ctrl.dispose();
  }

  void _syncRangeFromText() {
    final minV = _parsedInt(_minCtrl.text) ?? 0;
    final maxV = _parsedInt(_maxCtrl.text) ?? _rangeMax.toInt();
    final fixed = _fixMinMax(minV, maxV);
    setState(() {
      _minRange = fixed.$1.toDouble().clamp(0, _rangeMax);
      _maxRange = fixed.$2.toDouble().clamp(0, _rangeMax);
    });
  }

  bool _hasMinMaxError() {
    final minV = _parsedInt(_minCtrl.text);
    final maxV = _parsedInt(_maxCtrl.text);
    if (minV == null || maxV == null) return false;
    return minV > maxV;
  }

  static int? _parsedInt(String? s) {
    final v = (s ?? '').trim();
    if (v.isEmpty) return null;
    // Accept simple "45 000" or "45,000" typed by users.
    final cleaned = v.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.isEmpty) return null;
    return int.tryParse(cleaned);
  }

  static (int, int) _fixMinMax(int minV, int maxV) {
    if (minV <= 0 && maxV <= 0) return (0, 0);
    if (maxV <= 0) return (minV, maxV);
    if (minV <= 0) return (minV, maxV);
    if (minV <= maxV) return (minV, maxV);
    return (maxV, minV);
  }

  static double _roundUp(double v, {double step = 1000}) {
    if (v <= 0) return step;
    return (math.max(1, (v / step).ceil()) * step).toDouble();
  }

  static String _fmtPrice(int v) {
    // Force LTR rendering for numeric groups inside RTL UI.
    const lrm = '‎';
    if (v <= 0) return '${lrm}0${lrm}';
    final s = v.toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final idx = s.length - i;
      b.write(s[i]);
      if (idx > 1 && idx % 3 == 1) b.write(' ');
    }
    return '${lrm}' + b.toString() + '${lrm}';
  }

  static String _tr(BuildContext c,
      {required String ar, required String fr, required String en}) {
    final code = Localizations.localeOf(c).languageCode.toLowerCase();
    if (code == 'fr') return fr;
    if (code == 'en') return en;
    return ar;
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w900)),
    );
  }
}

enum _ChipKind { wilaya, moughataa, neighborhood, category, sub, sort, price }

class _ActiveChips extends StatelessWidget {
  const _ActiveChips({
    required this.wilayaId,
    required this.moughataaId,
    required this.neighborhood,
    required this.categoryId,
    required this.subCategoryId,
    required this.sort,
    required this.minPrice,
    required this.maxPrice,
    required this.onClear,
  });

  final String? wilayaId;
  final String? moughataaId;
  final String? neighborhood;
  final String? categoryId;
  final String? subCategoryId;
  final SearchSort sort;
  final int? minPrice;
  final int? maxPrice;
  final void Function(_ChipKind kind) onClear;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final loc = Localizations.localeOf(context);
    final chips = <Widget>[];

    void addChip(String label, _ChipKind kind, IconData icon) {
      chips.add(
        InputChip(
          avatar: Icon(icon, size: 16, color: cs.primary),
          label: Text(label),
          onDeleted: () => onClear(kind),
          deleteIcon: const Icon(Icons.close_rounded, size: 18),
          shape: StadiumBorder(
            side: BorderSide(color: cs.outlineVariant.withOpacity(0.55)),
          ),
          backgroundColor: cs.surface,
        ),
      );
    }

    if (wilayaId != null) {
      final w = findWilayaById(wilayaId!);
      addChip(w?.name.ofLocale(loc) ?? wilayaId!, _ChipKind.wilaya,
          Icons.place_outlined);
    }
    if (wilayaId != null && moughataaId != null) {
      final w = findWilayaById(wilayaId!);
      final m = w?.moughataas
          .where((x) => x.id == moughataaId)
          .cast<Moughataa?>()
          .firstWhere((x) => x != null, orElse: () => null);
      addChip(
        m?.name.ofLocale(loc) ?? moughataaId!,
        _ChipKind.moughataa,
        Icons.location_city_outlined,
      );
    }

    if (neighborhood != null && neighborhood!.trim().isNotEmpty) {
      addChip(neighborhood!.trim(), _ChipKind.neighborhood,
          Icons.home_work_outlined);
    }

    if (categoryId != null) {
      final c = findCategoryById(categoryId!);
      addChip(c?.name.ofLocale(loc) ?? categoryId!, _ChipKind.category,
          Icons.category_outlined);
    }
    if (categoryId != null && subCategoryId != null) {
      final c = findCategoryById(categoryId!);
      final s = c == null
          ? null
          : withOtherSubcategory(c.sub)
              .where((x) => x.id == subCategoryId)
              .cast<SubCategory?>()
              .firstWhere((x) => x != null, orElse: () => null);
      addChip(s?.name.ofLocale(loc) ?? subCategoryId!, _ChipKind.sub,
          Icons.layers_outlined);
    }

    final hasPrice = (minPrice != null && minPrice! > 0) ||
        (maxPrice != null && maxPrice! > 0);
    if (hasPrice) {
      final a = _FiltersSheetState._fmtPrice(minPrice ?? 0);
      const lrm = '‎';
      final b = maxPrice == null
          ? '${lrm}∞${lrm}'
          : _FiltersSheetState._fmtPrice(maxPrice!);
      addChip('${lrm}' + a + ' - ' + b + '${lrm}', _ChipKind.price,
          Icons.payments_outlined);
    }

    if (sort != SearchSort.newest) {
      addChip(_sortLabel(context, sort), _ChipKind.sort, Icons.sort_rounded);
    }

    if (chips.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: chips,
      ),
    );
  }

  String _sortLabel(BuildContext context, SearchSort s) {
    String tr({required String ar, required String fr, required String en}) {
      final code = Localizations.localeOf(context).languageCode.toLowerCase();
      if (code == 'fr') return fr;
      if (code == 'en') return en;
      return ar;
    }

    switch (s) {
      case SearchSort.newest:
        return tr(ar: 'الأحدث', fr: 'Plus récent', en: 'Newest');
      case SearchSort.oldest:
        return tr(ar: 'الأقدم', fr: 'Plus ancien', en: 'Oldest');
      case SearchSort.priceLow:
        return tr(ar: 'الأرخص', fr: 'Moins cher', en: 'Cheapest');
      case SearchSort.priceHigh:
        return tr(ar: 'الأغلى', fr: 'Plus cher', en: 'Most expensive');
    }
  }
}

class _SortSegmented extends StatelessWidget {
  const _SortSegmented({required this.value, required this.onChanged});
  final SearchSort value;
  final ValueChanged<SearchSort> onChanged;

  @override
  Widget build(BuildContext context) {
    String tr({required String ar, required String fr, required String en}) {
      final code = Localizations.localeOf(context).languageCode.toLowerCase();
      if (code == 'fr') return fr;
      if (code == 'en') return en;
      return ar;
    }

    final cs = Theme.of(context).colorScheme;
    final side = BorderSide(color: cs.outlineVariant.withOpacity(0.65));

    ChoiceChip chip(
        {required SearchSort v,
        required String label,
        required IconData icon}) {
      final selected = value == v;
      return ChoiceChip(
        selected: selected,
        onSelected: (_) => onChanged(v),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontWeight: FontWeight.w900,
              color: selected ? cs.onPrimaryContainer : cs.onSurface),
        ),
        avatar: Icon(icon,
            size: 18, color: selected ? cs.onPrimaryContainer : cs.primary),
        shape: StadiumBorder(side: side),
        backgroundColor: cs.surface,
        selectedColor: cs.primaryContainer,
        labelPadding: const EdgeInsetsDirectional.fromSTEB(8, 0, 10, 0),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
    }

    // ✅ Wrap prevents text clipping in Arabic/French (unlike SegmentedButton).
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        chip(
          v: SearchSort.newest,
          label: tr(ar: 'الأحدث', fr: 'Plus récent', en: 'Newest'),
          icon: Icons.new_releases_outlined,
        ),
        chip(
          v: SearchSort.priceLow,
          label: tr(ar: 'الأرخص', fr: 'Moins cher', en: 'Cheapest'),
          icon: Icons.arrow_downward_rounded,
        ),
        chip(
          v: SearchSort.priceHigh,
          label: tr(ar: 'الأغلى', fr: 'Plus cher', en: 'Most expensive'),
          icon: Icons.arrow_upward_rounded,
        ),
        chip(
          v: SearchSort.oldest,
          label: tr(ar: 'الأقدم', fr: 'Plus ancien', en: 'Oldest'),
          icon: Icons.history,
        ),
      ],
    );
  }
}
