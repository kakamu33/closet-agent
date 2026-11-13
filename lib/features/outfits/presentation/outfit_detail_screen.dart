import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/detail_layout.dart';

import '../../../core/providers.dart';
import '../../../core/widgets/detail_photo_gallery.dart';
import '../../../core/widgets/item_image.dart';
import '../../wardrobe/presentation/item_detail_screen.dart';
import '../domain/outfit.dart';
import 'outfit_form_screen.dart';

class OutfitDetailScreen extends ConsumerStatefulWidget {
  const OutfitDetailScreen({super.key, required this.outfit});
  final Outfit outfit;
  @override
  ConsumerState<OutfitDetailScreen> createState() => _OutfitDetailScreenState();
}

class _OutfitDetailScreenState extends ConsumerState<OutfitDetailScreen> {
  late Outfit _outfit = widget.outfit;
  bool _deleting = false;

  Future<void> _edit() async {
    final updated = await Navigator.push<Outfit>(
      context,
      MaterialPageRoute(builder: (_) => OutfitFormScreen(outfit: _outfit)),
    );
    if (updated != null && mounted) setState(() => _outfit = updated);
  }

  Future<void> _delete() async {
    if (_deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这套搭配？'),
        content: const Text('衣橱中的单品会保留。'),
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
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await ref.read(outfitsProvider.notifier).remove(_outfit.id);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('删除失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final latest = ref
        .watch(outfitsProvider)
        .value
        ?.where((outfit) => outfit.id == _outfit.id)
        .firstOrNull;
    if (latest != null) _outfit = latest;
    final tags = ref.watch(outfitTagsProvider).value ?? const [];
    final items = ref.watch(wardrobeItemsProvider);
    final tagNames = _outfit.tags
        .map(
          (id) => tags
              .where((tag) => tag.id == id)
              .map((tag) => tag.name)
              .firstOrNull,
        )
        .whereType<String>()
        .toList();
    final entryPhotos = _outfit.entries
        .map((entry) {
          final current = items.value
              ?.where((item) => item.id == entry.itemId)
              .firstOrNull;
          return current?.imagePath ?? entry.imagePath;
        })
        .whereType<String>()
        .toSet()
        .toList();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F5F1),
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: '编辑搭配',
            onPressed: _deleting ? null : _edit,
            icon: const Icon(Icons.edit_outlined, size: 20),
          ),
          PopupMenuButton<String>(
            tooltip: '更多操作',
            enabled: !_deleting,
            icon: const Icon(Icons.more_horiz, size: 22),
            color: const Color(0xFFFCFBF8),
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'delete',
                child: Text('删除搭配', style: TextStyle(fontSize: 14)),
              ),
            ],
            onSelected: (_) => _delete(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          DetailPhotoGallery(
            paths: _outfit.photos.isNotEmpty ? _outfit.photos : entryPhotos,
          ),
          DetailHeading(
            title: _outfit.name,
            category: tagNames.join(' · '),
            kind: '搭配档案',
          ),
          if (_outfit.photos.isEmpty && entryPhotos.isNotEmpty) ...[
            const SizedBox(height: 6),
            const Text(
              '单品照片',
              style: TextStyle(fontSize: 11, color: Color(0xFF918A82)),
            ),
          ],
          DetailSectionTitle(
            title: '搭配单品',
            annotation: '${_outfit.entries.length} 件',
          ),
          for (var i = 0; i < _outfit.entries.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, indent: 64, color: Color(0xFFE5E0D9)),
            Builder(
              builder: (context) {
                final entry = _outfit.entries[i];
                final item = items.value
                    ?.where((item) => item.id == entry.itemId)
                    .firstOrNull;
                final status = item != null
                    ? null
                    : !entry.isLinked
                    ? '未录入衣橱'
                    : items.isLoading
                    ? '正在查找单品'
                    : items.hasError
                    ? '单品暂时无法加载'
                    : '已从衣橱移除';
                return Material(
                  color: Colors.transparent,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                    horizontalTitleGap: 12,
                    leading: ItemImage(
                      path: item?.imagePath ?? entry.imagePath,
                      size: 52,
                      radius: 6,
                    ),
                    title: Text(
                      item?.name ?? entry.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: status == null
                        ? null
                        : Text(
                            status,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF807B74),
                            ),
                          ),
                    trailing: item == null
                        ? null
                        : const Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: Color(0xFFABA298),
                          ),
                    onTap: item == null
                        ? null
                        : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ItemDetailScreen(item: item),
                            ),
                          ),
                  ),
                );
              },
            ),
          ],
          if (_outfit.notes?.trim().isNotEmpty == true) ...[
            const DetailSectionTitle(title: '搭配笔记'),
            Text(
              _outfit.notes!.trim(),
              style: const TextStyle(fontSize: 14, height: 1.7),
            ),
          ],
          DetailRecordTime(
            created: _outfit.createdAt,
            updated: _outfit.updatedAt,
            label: '保存',
          ),
        ],
      ),
    );
  }
}
