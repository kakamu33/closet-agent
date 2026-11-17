import 'item_attribute_editor.dart';
import '../../../core/media/photo_editor.dart';
import '../../assistant/presentation/assistant_screen.dart';
import '../../outfits/presentation/outfit_form_screen.dart';
import '../domain/item_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/detail_layout.dart';

import '../../../core/providers.dart';
import '../../../core/widgets/detail_photo_gallery.dart';
import '../../../core/widgets/item_image.dart';
import '../../outfits/presentation/outfit_detail_screen.dart';
import '../data/background_removal_service.dart';
import '../domain/wardrobe_item.dart';
import 'item_form_screen.dart';

class ItemDetailScreen extends ConsumerStatefulWidget {
  const ItemDetailScreen({super.key, required this.item});
  final WardrobeItem item;

  @override
  ConsumerState<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends ConsumerState<ItemDetailScreen> {
  late WardrobeItem _item = widget.item;
  String? _removingPath;
  bool _savingAttribute = false;

  Future<void> _editAttribute(String field) async {
    if (_savingAttribute) return;
    final owner = ref.read(authSessionProvider).value?.id;
    final controller = ref.read(wardrobeItemsProvider.notifier);
    final before = _item;
    final value = await editItemAttribute(context, before, field);
    if (value == null ||
        !mounted ||
        ref.read(authSessionProvider).value?.id != owner) {
      return;
    }
    setState(() => _savingAttribute = true);
    try {
      await controller.updateAttribute(before, field, value);
      if (!mounted || ref.read(authSessionProvider).value?.id != owner) return;
      final current = (await ref.read(
        wardrobeItemsProvider.future,
      )).where((i) => i.id == before.id).firstOrNull;
      if (mounted &&
          current != null &&
          ref.read(authSessionProvider).value?.id == owner) {
        setState(() => _item = current);
      }
    } catch (error) {
      if (mounted) _showMessage('保存失败：$error');
    } finally {
      if (mounted) setState(() => _savingAttribute = false);
    }
  }

  Future<void> _moreAttributes() async {
    final owner = ref.read(authSessionProvider).value?.id;
    final field = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFFFCFBF8),
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .7,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 12),
                child: Text(
                  '单品属性',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              for (final entry in itemAttributeLabels.entries)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  title: Text(
                    entry.value,
                    style: const TextStyle(fontSize: 14),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => Navigator.pop(context, entry.key),
                ),
            ],
          ),
        ),
      ),
    );
    if (field != null &&
        mounted &&
        ref.read(authSessionProvider).value?.id == owner) {
      await _editAttribute(field);
    }
  }

  Widget _attributeChip(String field, String label, {Color? background}) =>
      Material(
        color: background ?? const Color(0xFFF0EDE7),
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          onTap: _savingAttribute ? null : () => _editAttribute(field),
          borderRadius: BorderRadius.circular(7),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      color: Color(0xFF514C43),
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                const Icon(
                  Icons.expand_more,
                  size: 14,
                  color: Color(0xFF8B8276),
                ),
              ],
            ),
          ),
        ),
      );

  Future<void> _editPhoto(String path, {bool restore = false}) async {
    if (_removingPath != null) return;
    final owner = ref.read(authSessionProvider).value?.id;
    final controller = ref.read(wardrobeItemsProvider.notifier);
    final before = _item;
    setState(() => _removingPath = path);
    try {
      final next = restore
          ? before.details.originals[path]
          : await editClothingPhoto(context, ref, path);
      if (next == null ||
          !mounted ||
          ref.read(authSessionProvider).value?.id != owner) {
        return;
      }
      final originals = {...before.details.originals}..remove(path);
      if (!restore) originals[next] = before.details.originals[path] ?? path;
      final updated = before.copyWith(
        imagePaths: before.imagePaths.map((p) => p == path ? next : p).toList(),
        details: before.details.copyWith(originals: originals),
        updatedAt: DateTime.now(),
      );
      await controller.save(updated);
      if (mounted && ref.read(authSessionProvider).value?.id == owner) {
        setState(() => _item = updated);
      }
    } catch (_) {
      if (mounted) _showMessage('图片保存失败，请重试；原图仍保留');
    } finally {
      if (mounted) setState(() => _removingPath = null);
    }
  }

  void _createOutfit() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => OutfitFormScreen(initialItems: [_item])),
  );

  Future<void> _confirmRemoveBackground(String path) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除图片背景？'),
        content: const Text('图片将上传至 Poof 处理，处理完成后会生成透明背景版本。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认去除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _removeBackground(path);
  }

  Future<void> _removeBackground(String path) async {
    final owner = ref.read(authSessionProvider).value?.id;
    final controller = ref.read(wardrobeItemsProvider.notifier);
    final before = _item;
    setState(() => _removingPath = path);
    try {
      final transparentImage = await ref
          .read(backgroundRemovalServiceProvider)
          .removeBackground(imagePath: path);
      if (!mounted || ref.read(authSessionProvider).value?.id != owner) return;
      final paths = before.imagePaths
          .map((entry) => entry == path ? transparentImage : entry)
          .toList();
      final originals = {...before.details.originals}..remove(path);
      originals[transparentImage] = before.details.originals[path] ?? path;
      final updated = before.copyWith(
        details: before.details.copyWith(originals: originals),
        imagePaths: paths,
        updatedAt: DateTime.now(),
      );
      await controller.save(updated);
      if (!mounted) return;
      setState(() => _item = updated);
      _showMessage('背景已去除，透明 PNG 已替换原图。');
    } on BackgroundRemovalException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('抠图失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _removingPath = null);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final latest = ref
        .watch(wardrobeItemsProvider)
        .value
        ?.where((item) => item.id == _item.id)
        .firstOrNull;
    if (latest != null) _item = latest;
    final related = ref.watch(itemOutfitsProvider(_item.id));
    final allTags = ref.watch(wardrobeTagsProvider).value ?? const [];
    final orderedIds = [..._item.tagIds]
      ..sort((a, b) {
        final pa =
            allTags.where((t) => t.id == a).firstOrNull?.isPrimary ?? false;
        final pb =
            allTags.where((t) => t.id == b).firstOrNull?.isPrimary ?? false;
        return pa == pb
            ? 0
            : pa
            ? -1
            : 1;
      });
    final tagNames = orderedIds
        .map(
          (id) => allTags
              .where((tag) => tag.id == id)
              .map((tag) => tag.name)
              .firstOrNull,
        )
        .whereType<String>()
        .toList();
    final attributes = <(String, String)>[
      if (_item.color?.isNotEmpty == true) ('color', '颜色 · ${_item.color}'),
      if (_item.details.seasons.isNotEmpty)
        ('seasons', _item.details.seasons.join(' · ')),
      if (_item.details.warmth?.isNotEmpty == true)
        ('warmth', '厚薄 · ${_item.details.warmth}'),
      if (_item.details.size?.isNotEmpty == true)
        ('size', '尺码 · ${_item.details.size}'),
      if (_item.details.material?.isNotEmpty == true)
        ('material', '材质 · ${_item.details.material}'),
      if (_item.brand?.isNotEmpty == true) ('brand', '品牌 · ${_item.brand}'),
      if (_item.price != null) ('price', '${_item.currency} ${_item.price}'),
    ];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F5F1),
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: '编辑单品',
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () async {
              final updated = await Navigator.push<WardrobeItem>(
                context,
                MaterialPageRoute(builder: (_) => ItemFormScreen(item: _item)),
              );
              if (updated != null && mounted) setState(() => _item = updated);
            },
          ),
          PopupMenuButton<String>(
            tooltip: '更多操作',
            icon: const Icon(Icons.more_horiz, size: 22),
            color: const Color(0xFFFCFBF8),
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'delete',
                child: Text('删除单品', style: TextStyle(fontSize: 14)),
              ),
            ],
            onSelected: (_) async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('删除这件单品？'),
                  content: const Text('已存在的搭配会保留单品名称，但不再跳转。'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('删除'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                try {
                  await ref
                      .read(wardrobeItemsProvider.notifier)
                      .remove(_item.id);
                  if (context.mounted) Navigator.pop(context);
                } catch (_) {
                  if (mounted) _showMessage('删除失败，请重试');
                }
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          DetailPhotoGallery(
            paths: _item.imagePaths,
            processingPath: _removingPath,
            onRemoveBackground: _confirmRemoveBackground,
            onEdit: _editPhoto,
            restorablePaths: _item.details.originals.keys.toSet(),
            onRestore: _item.details.originals.isEmpty
                ? null
                : (path) => _editPhoto(path, restore: true),
          ),
          DetailHeading(
            title: _item.name,
            category: tagNames.join(' · '),
            kind: '单品档案',
          ),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _attributeChip(
                'status',
                ItemDetails.statusLabels[_item.details.status] ?? '可穿',
                background: switch (_item.details.status) {
                  'laundry' => const Color(0xFFE1EBF1),
                  'paused' => const Color(0xFFEAE4ED),
                  _ => const Color(0xFFE7EDE2),
                },
              ),
              for (final attribute in attributes)
                _attributeChip(attribute.$1, attribute.$2),
              TextButton(
                onPressed: _savingAttribute ? null : _moreAttributes,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF80786B),
                  textStyle: const TextStyle(fontSize: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                ),
                child: Text(_savingAttribute ? '保存中…' : '+ 补充属性'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _item.details.status == 'ready'
                  ? () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AssistantScreen(requiredItem: _item),
                      ),
                    )
                  : null,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF705841),
                side: const BorderSide(color: Color(0xFFD8D0C4)),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.auto_awesome_outlined, size: 16),
              label: const Text('用这件帮我搭配'),
            ),
          ),
          if (_item.notes?.trim().isNotEmpty == true) ...[
            const DetailSectionTitle(title: '单品笔记'),
            InkWell(
              onTap: () => _editAttribute('notes'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  _item.notes!.trim(),
                  style: const TextStyle(fontSize: 14, height: 1.7),
                ),
              ),
            ),
          ],
          DetailSectionTitle(
            title: '相关搭配',
            annotation: related.asData == null
                ? null
                : '${related.asData!.value.length} 套',
          ),
          related.when(
            data: (outfits) => outfits.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '还没有使用这件单品的搭配',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF807B74),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _createOutfit,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('创建搭配'),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: outfits
                        .map(
                          (outfit) => Material(
                            color: const Color(0xFFFCFBF8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: ListTile(
                              contentPadding: const EdgeInsets.fromLTRB(
                                12,
                                8,
                                12,
                                8,
                              ),
                              hoverColor: Colors.transparent,
                              splashColor: Colors.transparent,
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(9),
                                child: SizedBox(
                                  width: 52,
                                  height: 52,
                                  child: outfit.photos.isEmpty
                                      ? ColoredBox(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.surfaceContainerHighest,
                                          child: const Icon(
                                            Icons.view_quilt_outlined,
                                            size: 23,
                                          ),
                                        )
                                      : ItemImage(
                                          path: outfit.photos.first,
                                          width: 52,
                                          height: 52,
                                          radius: 0,
                                        ),
                                ),
                              ),
                              title: Text(
                                outfit.name,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              subtitle: Text(
                                '${outfit.entries.length} 件单品',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF807B74),
                                ),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      OutfitDetailScreen(outfit: outfit),
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
            loading: () => const LinearProgressIndicator(),
            error: (error, _) => Text('加载失败：$error'),
          ),
          DetailRecordTime(created: _item.createdAt, updated: _item.updatedAt),
        ],
      ),
    );
  }
}
