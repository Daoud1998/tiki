import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/ma_catalog.dart';

class ImageSearchScreen extends StatefulWidget {
  const ImageSearchScreen({super.key, required this.imagePath});

  final String imagePath;

  @override
  State<ImageSearchScreen> createState() => _ImageSearchScreenState();
}

class _ImageSearchScreenState extends State<ImageSearchScreen> {
  final _qCtl = TextEditingController();

  String? _categoryId;
  String? _subCategoryId;

  @override
  void dispose() {
    _qCtl.dispose();
    super.dispose();
  }

  String _tr(BuildContext c,
      {required String ar, required String fr, required String en}) {
    final code = Localizations.localeOf(c).languageCode.toLowerCase();
    if (code == 'fr') return fr;
    if (code == 'en') return en;
    return ar;
  }

  String _l10n(L10n3 v) {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    if (code == 'fr') return v.fr;
    if (code == 'en') return v.en;
    return v.ar;
  }

  CategoryNode? get _selectedCat {
    if (_categoryId == null) return null;
    for (final c in maCategories) {
      if (c.id == _categoryId) return c;
    }
    return null;
  }

  void _apply() {
    final qp = <String, String>{};

    final q = _qCtl.text.trim();
    if (q.isNotEmpty) qp['q'] = q;

    if ((_categoryId ?? '').isNotEmpty) qp['cat'] = _categoryId!;
    if ((_subCategoryId ?? '').isNotEmpty) qp['sub'] = _subCategoryId!;

    final uri = Uri(path: '/search', queryParameters: qp);
    context.go(uri.toString());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_tr(context,
            ar: 'بحث بالصورة', fr: "Recherche par image", en: 'Image search')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Preview
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: widget.imagePath.isEmpty
                  ? Container(
                      color: cs.surfaceContainerHighest,
                      alignment: Alignment.center,
                      child: Icon(Icons.image_not_supported_outlined,
                          color: cs.onSurfaceVariant, size: 42),
                    )
                  : Image.file(
                      File(widget.imagePath),
                      fit: BoxFit.cover,
                      errorBuilder: (c, _, __) => Container(
                        color: cs.surfaceContainerHighest,
                        alignment: Alignment.center,
                        child: Icon(Icons.broken_image_outlined,
                            color: cs.onSurfaceVariant, size: 42),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _tr(
              context,
              ar: 'ساعدني بفئة تقريبية، وسأعرض لك نتائج داخلها. (نسخة ذكية وخفيفة بدون سيرفر)',
              fr: "Choisissez une catégorie approximative, puis je filtre les résultats. (AI‑lite sans serveur)",
              en: 'Pick a rough category and I will filter results. (AI‑lite without a server)',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),

          // Category chips
          Text(_tr(context, ar: 'الفئة', fr: 'Catégorie', en: 'Category'),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in maCategories)
                ChoiceChip(
                  label: Text(_l10n(c.name)),
                  selected: _categoryId == c.id,
                  onSelected: (_) => setState(() {
                    _categoryId = c.id;
                    _subCategoryId = null;
                  }),
                ),
            ],
          ),

          if (_selectedCat != null && _selectedCat!.sub.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
                _tr(context,
                    ar: 'قسم فرعي (اختياري)',
                    fr: 'Sous-catégorie (optionnel)',
                    en: 'Subcategory (optional)'),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in _selectedCat!.sub)
                  ChoiceChip(
                    label: Text(_l10n(s.name)),
                    selected: _subCategoryId == s.id,
                    onSelected: (_) => setState(() => _subCategoryId = s.id),
                  ),
              ],
            ),
          ],

          const SizedBox(height: 14),
          TextField(
            controller: _qCtl,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: _tr(context,
                  ar: 'أضف كلمة (اختياري)',
                  fr: 'Ajoutez un mot (optionnel)',
                  en: 'Add a word (optional)'),
              hintText: _tr(context,
                  ar: 'مثال: آيفون، شقة، تويوتا…',
                  fr: 'Ex: iPhone, appartement, Toyota…',
                  en: 'E.g. iPhone, apartment, Toyota…'),
              filled: true,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none),
            ),
            onSubmitted: (_) => _apply(),
          ),
          const SizedBox(height: 14),

          FilledButton.icon(
            onPressed: _apply,
            icon: const Icon(Icons.search),
            label: Text(_tr(context,
                ar: 'اعرض النتائج',
                fr: 'Voir les résultats',
                en: 'Show results')),
          ),
          const SizedBox(height: 8),
          Text(
            _tr(
              context,
              ar: 'ملاحظة: لاحقاً يمكننا ترقية البحث إلى “تشابه صور” حقيقي عبر Embeddings.',
              fr: "Note: plus tard, on peut upgrader vers une vraie similarité d'images (embeddings).",
              en: 'Note: later we can upgrade to true visual similarity using embeddings.',
            ),
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
