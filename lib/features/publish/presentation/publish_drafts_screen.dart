import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/ma_catalog.dart';
import '../../../core/state/auth_state.dart' as auth;
import '../../product/domain/app_product.dart';
import 'data/publish_drafts_repository.dart';
import 'domain/publish_draft.dart';
import 'publish_drafts_controller.dart';

class PublishDraftsScreen extends ConsumerStatefulWidget {
  const PublishDraftsScreen({super.key, this.extra});
  final Object? extra;

  @override
  ConsumerState<PublishDraftsScreen> createState() =>
      _PublishDraftsScreenState();
}

class _PublishDraftsScreenState extends ConsumerState<PublishDraftsScreen> {
  String tr({required String ar, required String fr, required String en}) {
    final code = Localizations.localeOf(context).languageCode;
    switch (code) {
      case 'fr':
        return fr;
      case 'en':
        return en;
      default:
        return ar;
    }
  }

  bool _selectionMode = false;
  final Set<String> _selected = <String>{};

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
  }

  void _toggleSelected(String id) {
    final did = id.trim();
    if (did.isEmpty) return;
    setState(() {
      if (_selected.contains(did)) {
        _selected.remove(did);
      } else {
        _selected.add(did);
      }
      if (_selected.isEmpty) _selectionMode = false;
    });
  }

  void _enterSelectionWith(String id) {
    final did = id.trim();
    if (did.isEmpty) return;
    setState(() {
      _selectionMode = true;
      _selected.add(did);
    });
  }

  void _toggleSelectAll(List<PublishDraft> drafts) {
    if (drafts.isEmpty) return;
    setState(() {
      _selectionMode = true;
      if (_selected.length == drafts.length) {
        _selected.clear();
        _selectionMode = false;
      } else {
        _selected
          ..clear()
          ..addAll(drafts.map((d) => d.id));
      }
    });
  }

  Future<void> _deleteSelected(List<PublishDraft> drafts) async {
    if (_selected.isEmpty) return;
    final count = _selected.length;

    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) {
            return AlertDialog(
              title: Text(tr(
                ar: 'حذف المسودات',
                fr: 'Supprimer',
                en: 'Delete drafts',
              )),
              content: Text(tr(
                ar: 'هل تريد حذف $count مسودة؟',
                fr: 'Supprimer $count brouillons ?',
                en: 'Delete $count drafts?',
              )),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(tr(ar: 'إلغاء', fr: 'Annuler', en: 'Cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(tr(ar: 'حذف', fr: 'Supprimer', en: 'Delete')),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!ok) return;
    await ref
        .read(publishDraftsControllerProvider.notifier)
        .deleteMany(_selected);
    if (mounted) _exitSelection();
  }

  @override
  void initState() {
    super.initState();

    // If caller passed a product via `extra`, we turn it into an Edit Draft,
    // then jump straight into the wizard.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ex = widget.extra;
      if (ex is AppProduct) {
        final id = await ref
            .read(publishDraftsControllerProvider.notifier)
            .createEditFromAppProduct(ex);
        if (!mounted) return;
        // Pass the product as extra so the wizard can prefill immediately.
        context.push('/publish/wizard/$id', extra: ex);
        return;
      }
    });
  }

  Future<void> _createNewDraft() async {
    final id = await ref
        .read(publishDraftsControllerProvider.notifier)
        .createBlank(kind: 'product');
    if (!mounted) return;
    context.push('/publish/wizard/$id');
  }

  Future<void> _continueDraft(String id) async {
    await ref.read(publishDraftsRepositoryProvider).setLastDraftId(id);
    if (!mounted) return;
    context.push('/publish/wizard/$id');
  }

  Future<void> _showPublishingBlockedDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(tr(
            ar: 'تم إيقاف النشر',
            fr: 'Publication désactivée',
            en: 'Publishing disabled',
          )),
          content: Text(tr(
            ar: 'تم منع حسابك من النشر مؤقتًا بواسطة الإدارة. إذا كنت ترى أن هذا خطأ، تواصل مع الدعم.',
            fr: 'Votre compte a été bloqué pour la publication par l\'administration. Si c\'est une erreur, contactez le support.',
            en: 'Your account has been temporarily blocked from publishing by admin. If this is a mistake, contact support.',
          )),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(tr(ar: 'حسناً', fr: 'OK', en: 'OK')),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteDraft(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(tr(
              ar: 'حذف المسودة',
              fr: 'Supprimer le brouillon',
              en: 'Delete draft')),
          content: Text(tr(
            ar: 'هل تريد حذف هذه المسودة؟',
            fr: 'Voulez-vous supprimer ce brouillon ?',
            en: 'Delete this draft?',
          )),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(tr(ar: 'إلغاء', fr: 'Annuler', en: 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(tr(ar: 'حذف', fr: 'Supprimer', en: 'Delete')),
            )
          ],
        );
      },
    );

    if (ok != true) return;
    await ref.read(publishDraftsControllerProvider.notifier).delete(id);
  }

  Future<void> _renameDraft(PublishDraft d) async {
    final ctl = TextEditingController(text: (d.name ?? '').trim());
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(tr(ar: 'إعادة تسمية', fr: 'Renommer', en: 'Rename')),
          content: TextField(
            controller: ctl,
            decoration: InputDecoration(
              hintText: tr(
                  ar: 'اسم المسودة', fr: 'Nom du brouillon', en: 'Draft name'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: Text(tr(ar: 'إلغاء', fr: 'Annuler', en: 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctl.text.trim()),
              child: Text(tr(ar: 'حفظ', fr: 'Enregistrer', en: 'Save')),
            ),
          ],
        );
      },
    );

    if (name == null) return;
    await ref.read(publishDraftsControllerProvider.notifier).rename(d.id, name);
  }

  String _draftTitle(PublishDraft d) {
    final explicit = (d.name ?? '').trim();
    if (explicit.isNotEmpty) return explicit;

    final title = ((d.data['title'] ?? '') as String).trim();
    if (title.isNotEmpty) return title;

    if (d.mode == 'edit') {
      return tr(
          ar: 'تعديل منتج', fr: 'Modifier une annonce', en: 'Edit listing');
    }
    return tr(ar: 'مسودة جديدة', fr: 'Nouveau brouillon', en: 'New draft');
  }

  String _draftSubtitle(PublishDraft d) {
    final rawCat = (d.data['categoryId'] ?? '').toString().trim();
    final rawSub = (d.data['subCategoryId'] ?? '').toString().trim();

    final catId = resolveCategoryIdAny(rawCat);
    final subId = resolveSubCategoryIdAny(rawSub);

    String? catLabel;
    if (catId != null) {
      for (final c in maCategories) {
        if (c.id == catId) {
          catLabel = c.name.of(context);
          break;
        }
      }
    } else if (rawCat.isNotEmpty) {
      catLabel = rawCat;
    }

    String? subLabel;
    if (subId != null) {
      // Prefer subcategories within the chosen category.
      if (catId != null) {
        for (final c in maCategories) {
          if (c.id == catId) {
            for (final s in c.subCategories) {
              if (s.id == subId) {
                subLabel = s.name.of(context);
                break;
              }
            }
          }
          if (subLabel != null) break;
        }
      }
      // Fallback: search globally.
      if (subLabel == null) {
        for (final c in maCategories) {
          for (final s in c.subCategories) {
            if (s.id == subId) {
              subLabel = s.name.of(context);
              break;
            }
          }
          if (subLabel != null) break;
        }
      }
    } else if (rawSub.isNotEmpty) {
      subLabel = rawSub;
    }

    final parts = <String>[];
    if ((catLabel ?? '').trim().isNotEmpty) parts.add(catLabel!.trim());
    if ((subLabel ?? '').trim().isNotEmpty) parts.add(subLabel!.trim());

    final updated = DateTime.fromMillisecondsSinceEpoch(d.updatedAtMs);
    final time = MaterialLocalizations.of(context).formatShortDate(updated);

    if (parts.isEmpty) return time;
    return '${parts.join(' · ')} · $time';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final blockedAsync = ref.watch(auth.publishingDisabledProvider);
    final publishingBlocked =
        blockedAsync.maybeWhen(data: (v) => v, orElse: () => false);
    final drafts = ref.watch(publishDraftsControllerProvider);
    final repo = ref.watch(publishDraftsRepositoryProvider);
    final lastId = (repo.getLastDraftId() ?? '').trim();

    final lastDraft = lastId.isEmpty
        ? null
        : drafts.cast<PublishDraft?>().firstWhere(
              (d) => d!.id == lastId,
              orElse: () => null,
            );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectionMode
              ? tr(
                  ar: 'تم اختيار ${_selected.length}',
                  fr: '${_selected.length} sélectionné(s)',
                  en: '${_selected.length} selected',
                )
              : tr(ar: 'المسودات', fr: 'Brouillons', en: 'Drafts'),
        ),
        actions: _selectionMode
            ? [
                IconButton(
                  tooltip: tr(
                      ar: 'تحديد الكل',
                      fr: 'Tout sélectionner',
                      en: 'Select all'),
                  onPressed: () => _toggleSelectAll(drafts),
                  icon: const Icon(Icons.select_all_rounded),
                ),
                IconButton(
                  tooltip: tr(ar: 'حذف', fr: 'Supprimer', en: 'Delete'),
                  onPressed:
                      _selected.isEmpty ? null : () => _deleteSelected(drafts),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
                IconButton(
                  tooltip: tr(ar: 'إلغاء', fr: 'Annuler', en: 'Cancel'),
                  onPressed: _exitSelection,
                  icon: const Icon(Icons.close_rounded),
                ),
              ]
            : [
                IconButton(
                  tooltip: tr(
                      ar: 'اختيار متعدد',
                      fr: 'Sélection multiple',
                      en: 'Multi select'),
                  onPressed: () {
                    setState(() => _selectionMode = true);
                  },
                  icon: const Icon(Icons.checklist_rtl_rounded),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'select_all') {
                      _toggleSelectAll(drafts);
                    }
                    if (v == 'delete_all') {
                      // Option B: select all first, then user confirms delete.
                      _toggleSelectAll(drafts);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(tr(
                            ar: 'تم تحديد الكل. اضغط حذف لإتمام العملية.',
                            fr: 'Tout est sélectionné. Appuyez sur Supprimer.',
                            en: 'All selected. Tap Delete to confirm.',
                          )),
                        ),
                      );
                    }
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      value: 'select_all',
                      child: Text(tr(
                          ar: 'تحديد الكل',
                          fr: 'Tout sélectionner',
                          en: 'Select all')),
                    ),
                    PopupMenuItem(
                      value: 'delete_all',
                      child: Text(tr(
                          ar: 'حذف الكل',
                          fr: 'Tout supprimer',
                          en: 'Delete all')),
                    ),
                  ],
                ),
              ],
      ),
      floatingActionButton: _selectionMode
          ? null
          : FloatingActionButton.extended(
              onPressed: publishingBlocked
                  ? _showPublishingBlockedDialog
                  : _createNewDraft,
              icon: const Icon(Icons.add_rounded),
              label: Text(tr(ar: 'نشر جديد', fr: 'Nouveau', en: 'New')),
            ),
      body: RefreshIndicator(
        onRefresh: () async {
          // Reload from storage.
          await ref.read(publishDraftsControllerProvider.notifier).load();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 120),
          children: [
            if (publishingBlocked) ...[
              Card(
                elevation: 0,
                color: cs.errorContainer.withAlpha(120),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.block_rounded, color: cs.error),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          tr(
                            ar: 'تم إيقاف النشر لحسابك من قبل الإدارة',
                            fr: 'La publication est désactivée pour votre compte',
                            en: 'Publishing is disabled for your account',
                          ),
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: cs.onErrorContainer,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _showPublishingBlockedDialog,
                        child: Text(
                            tr(ar: 'تفاصيل', fr: 'Détails', en: 'Details')),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (!_selectionMode && lastDraft != null) ...[
              Card(
                elevation: 0,
                color: cs.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.play_circle_fill_rounded,
                          color: cs.primary, size: 28),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr(
                                ar: 'متابعة آخر مسودة',
                                fr: 'Continuer le dernier brouillon',
                                en: 'Continue last draft',
                              ),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 15),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _draftTitle(lastDraft),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  TextStyle(color: cs.onSurface.withAlpha(190)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: publishingBlocked
                            ? _showPublishingBlockedDialog
                            : () => _continueDraft(lastDraft.id),
                        child: Text(
                            tr(ar: 'متابعة', fr: 'Continuer', en: 'Continue')),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (drafts.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 36),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.note_add_outlined,
                          size: 54, color: cs.onSurface.withAlpha(140)),
                      const SizedBox(height: 10),
                      Text(
                        tr(
                          ar: 'لا توجد مسودات بعد',
                          fr: 'Aucun brouillon',
                          en: 'No drafts yet',
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        tr(
                          ar: 'ابدأ نشرًا جديدًا، وسيتم الحفظ تلقائيًا.',
                          fr: 'Commencez, l’enregistrement est automatique.',
                          en: 'Start a new publish, autosave is on.',
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onSurface.withAlpha(180)),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: publishingBlocked
                            ? _showPublishingBlockedDialog
                            : _createNewDraft,
                        icon: const Icon(Icons.add_rounded),
                        label:
                            Text(tr(ar: 'نشر جديد', fr: 'Nouveau', en: 'New')),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...drafts.map((d) {
                final selected = _selected.contains(d.id);
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    onLongPress:
                        _selectionMode ? null : () => _enterSelectionWith(d.id),
                    leading: _selectionMode
                        ? Checkbox(
                            value: selected,
                            onChanged: (_) => _toggleSelected(d.id),
                          )
                        : CircleAvatar(
                            backgroundColor: cs.surfaceContainerHighest,
                            child: Icon(
                              d.mode == 'edit'
                                  ? Icons.edit_rounded
                                  : Icons.description_outlined,
                              color: cs.primary,
                            ),
                          ),
                    title: Text(
                      _draftTitle(d),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(
                      _draftSubtitle(d),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _selectionMode
                        ? _toggleSelected(d.id)
                        : _continueDraft(d.id),
                    trailing: _selectionMode
                        ? null
                        : PopupMenuButton<String>(
                            onSelected: (v) async {
                              switch (v) {
                                case 'continue':
                                  await _continueDraft(d.id);
                                  break;
                                case 'rename':
                                  await _renameDraft(d);
                                  break;
                                case 'duplicate':
                                  final id = await ref
                                      .read(publishDraftsControllerProvider
                                          .notifier)
                                      .duplicate(d.id);
                                  if (!mounted) return;
                                  context.push('/publish/wizard/$id');
                                  break;
                                case 'delete':
                                  await _deleteDraft(d.id);
                                  break;
                              }
                            },
                            itemBuilder: (ctx) {
                              return <PopupMenuEntry<String>>[
                                PopupMenuItem(
                                  value: 'continue',
                                  child: Text(tr(
                                      ar: 'متابعة',
                                      fr: 'Continuer',
                                      en: 'Continue')),
                                ),
                                PopupMenuItem(
                                  value: 'rename',
                                  child: Text(tr(
                                      ar: 'إعادة تسمية',
                                      fr: 'Renommer',
                                      en: 'Rename')),
                                ),
                                PopupMenuItem(
                                  value: 'duplicate',
                                  child: Text(tr(
                                      ar: 'نسخ',
                                      fr: 'Dupliquer',
                                      en: 'Duplicate')),
                                ),
                                const PopupMenuDivider(),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(
                                    tr(
                                        ar: 'حذف',
                                        fr: 'Supprimer',
                                        en: 'Delete'),
                                    style: TextStyle(color: cs.error),
                                  ),
                                ),
                              ];
                            },
                          ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
