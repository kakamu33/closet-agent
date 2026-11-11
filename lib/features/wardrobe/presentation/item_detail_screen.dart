import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers.dart';
import '../../../core/widgets/cutout_wand_button.dart';
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
        : '未知';
    final color = _item.color?.trim().isNotEmpty == true
        ? _item.color!.trim()
        : '未知';
    final timestamp = DateFormat('y.M.d HH:mm:ss');
    final price = _item.price == null
        ? null
        : '${_item.currency} ${_item.price!.toStringAsFixed(_item.price! % 1 == 0 ? 0 : 2)}';
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final updated = await Navigator.push<WardrobeItem>(
                context,
                MaterialPageRoute(builder: (_) => ItemFormScreen(item: _item)),
              );
              if (updated != null && mounted) setState(() => _item = updated);
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
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
                await ref.read(wardrobeItemsProvider.notifier).remove(_item.id);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          _ItemPhotoCarousel(
            paths: _item.imagePaths,
            removingPath: _removingPath,
            onRemoveBackground: _confirmRemoveBackground,
          ),
          const SizedBox(height: 22),
          Text(
            _item.name,
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            '品牌：$brand   ·    $color',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (price != null) ...[
            const SizedBox(height: 6),
            Text(
              '价格：$price',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tagNames.map((name) => Chip(label: Text(name))).toList(),
          ),
          const SizedBox(height: 24),
          Text('备注', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              _item.notes?.trim().isNotEmpty == true
                  ? _item.notes!.trim()
                  : '暂无说明',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: _item.notes?.trim().isNotEmpty == true
                    ? null
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 32),
          Text('相关搭配', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          related.when(
            data: (outfits) => outfits.isEmpty
                ? const Text('还没有使用这件单品的搭配。')
                : Column(
                    children: outfits
                        .map(
                          (outfit) => Card(
                            clipBehavior: Clip.antiAlias,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.fromLTRB(
                                10,
                                7,
                                8,
                                7,
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
                                            Icons.auto_awesome_outlined,
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
                              title: Text(outfit.name),
                              subtitle: Text('${outfit.entries.length}件单品'),
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
          const SizedBox(height: 28),
          Text(
            '创建于 ${timestamp.format(_item.createdAt.toLocal())}\n更新于 ${timestamp.format(_item.updatedAt.toLocal())}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemPhotoCarousel extends StatefulWidget {
  const _ItemPhotoCarousel({
    required this.paths,
    required this.removingPath,
    required this.onRemoveBackground,
  });
  final List<String> paths;
  final String? removingPath;
  final ValueChanged<String> onRemoveBackground;

  @override
  State<_ItemPhotoCarousel> createState() => _ItemPhotoCarouselState();
}

class _ItemPhotoCarouselState extends State<_ItemPhotoCarousel> {
  var _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    final currentPath = widget.paths.isEmpty
        ? null
        : widget.paths[_currentPage.clamp(0, widget.paths.length - 1)];
    final processing =
        currentPath != null && currentPath == widget.removingPath;
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: SizedBox(
        height: 300,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView(
              onPageChanged: (page) => setState(() => _currentPage = page),
              children: widget.paths.isEmpty
                  ? [ItemImage(path: null, radius: 0)]
                  : widget.paths
                        .map((path) => ItemImage(path: path, radius: 0))
                        .toList(),
            ),
            if (processing)
              const ColoredBox(
                color: Color(0x66000000),
                child: Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
            if (currentPath != null && !processing)
              Positioned(
                left: 14,
                bottom: 14,
                child: CutoutWandButton(
                  onTap: () => widget.onRemoveBackground(currentPath),
                ),
              ),
            if (widget.paths.length > 1)
              Positioned(
                right: 12,
                bottom: 12,
                child: _PhotoPageIndicator(
                  currentPage: _currentPage,
                  total: widget.paths.length,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PhotoPageIndicator extends StatelessWidget {
  const _PhotoPageIndicator({required this.currentPage, required this.total});
  final int currentPage;
  final int total;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      child: Text(
        '${currentPage + 1}/$total',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
  );
}
