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
    setState(() => _removingPath = path);
    try {
      final transparentImage = await ref
          .read(backgroundRemovalServiceProvider)
          .removeBackground(imagePath: path);
      final paths = _item.imagePaths
          .map((entry) => entry == path ? transparentImage : entry)
          .toList();
      final updated = _item.copyWith(
        imagePaths: paths,
        updatedAt: DateTime.now(),
      );
      await ref.read(wardrobeItemsProvider.notifier).save(updated);
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
    final tagNames = _item.tagIds
        .map(
          (id) => allTags
              .where((tag) => tag.id == id)
              .map((tag) => tag.name)
              .firstOrNull,
        )
        .whereType<String>()
        .toList();
    final brand = _item.brand?.trim().isNotEmpty == true
        ? _item.brand!.trim()
        : null;
    final color = _item.color?.trim().isNotEmpty == true
        ? _item.color!.trim()
        : null;
    final price = _item.price == null
        ? null
        : '${_item.currency} ${_item.price!.toStringAsFixed(_item.price! % 1 == 0 ? 0 : 2)}';
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
          ),
          DetailHeading(
            title: _item.name,
            category: tagNames.join(' · '),
            kind: '单品档案',
          ),
          if (brand != null || color != null || price != null)
            DetailFacts(
              values: [
                if (brand != null) ('品牌', brand),
                if (color != null) ('颜色', color),
                if (price != null) ('购入价格', price),
              ],
            ),
          if (_item.notes?.trim().isNotEmpty == true) ...[
            const DetailSectionTitle(title: '单品笔记'),
            Text(
              _item.notes!.trim(),
              style: const TextStyle(fontSize: 14, height: 1.7),
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
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '还没有使用这件单品的搭配',
                      style: TextStyle(fontSize: 13, color: Color(0xFF807B74)),
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
