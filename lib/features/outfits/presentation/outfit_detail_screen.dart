import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers.dart';
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
  late Outfit _outfit;

  @override
  void initState() {
    super.initState();
    _outfit = widget.outfit;
  }

  Future<void> _edit() async {
    final updated = await Navigator.push<Outfit>(
      context,
      MaterialPageRoute(builder: (_) => OutfitFormScreen(outfit: _outfit)),
    );
    if (updated != null && mounted) setState(() => _outfit = updated);
  }

  @override
  Widget build(BuildContext context) {
    final tags = ref.watch(outfitTagsProvider).value ?? const [];
    final tagNames = _outfit.tags
        .map((id) => tags.where((tag) => tag.id == id).map((tag) => tag.name).firstOrNull)
        .whereType<String>()
        .toList();
    final timestamp = DateFormat('y.M.d HH:mm:ss');
    return Scaffold(
      appBar: AppBar(actions: [
        IconButton(onPressed: _edit, icon: const Icon(Icons.edit_outlined)),
        IconButton(
          onPressed: () async {
            await ref.read(outfitsProvider.notifier).remove(_outfit.id);
            if (context.mounted) Navigator.pop(context);
          },
          icon: const Icon(Icons.delete_outline),
        ),
      ]),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          _OutfitPhotoCarousel(paths: _outfit.photos),
          const SizedBox(height: 22),
          Text(_outfit.name, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          if (tagNames.isNotEmpty)
            Text(tagNames.join(' · '), style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.primary)),
          if (_outfit.notes?.isNotEmpty == true) ...[
            const SizedBox(height: 16),
            Text(_outfit.notes!, style: Theme.of(context).textTheme.bodyLarge),
          ],
          const SizedBox(height: 28),
          Text('${_outfit.entries.length} 件单品', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          ..._outfit.entries.map((entry) => Card(
            margin: const EdgeInsets.only(bottom: 10),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: ListTile(
              hoverColor: Colors.transparent,
              splashColor: Colors.transparent,
              leading: ItemImage(path: entry.imagePath, size: 52, radius: 12),
              title: Text(entry.name),
              subtitle: Text(entry.isLinked ? '已录入 · 点击查看' : '未录入单品'),
              trailing: entry.isLinked ? const Icon(Icons.chevron_right) : null,
              onTap: !entry.isLinked ? null : () {
                final item = (ref.read(wardrobeItemsProvider).value ?? []).where((value) => value.id == entry.itemId).firstOrNull;
                if (item != null) Navigator.push(context, MaterialPageRoute(builder: (_) => ItemDetailScreen(item: item)));
              },
            ),
          )),
          const SizedBox(height: 18),
          Text(
            '创建于 ${timestamp.format(_outfit.createdAt.toLocal())}\n更新于 ${timestamp.format(_outfit.updatedAt.toLocal())}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _OutfitPhotoCarousel extends StatefulWidget {
  const _OutfitPhotoCarousel({required this.paths});
  final List<String> paths;

  @override
  State<_OutfitPhotoCarousel> createState() => _OutfitPhotoCarouselState();
}

class _OutfitPhotoCarouselState extends State<_OutfitPhotoCarousel> {
  var _currentPage = 0;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(28),
    child: SizedBox(
      height: 220,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.paths.isEmpty
              ? Container(
                  decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFD9CDC0), Color(0xFFA9B0A1)])),
                  child: const Icon(Icons.auto_awesome, size: 58, color: Colors.white),
                )
              : PageView(
                  onPageChanged: (page) => setState(() => _currentPage = page),
                  children: widget.paths.map((path) => ItemImage(path: path, radius: 0)).toList(),
                ),
          if (widget.paths.length > 1)
            Positioned(
              right: 12,
              bottom: 12,
              child: _PhotoCountIndicator(currentPage: _currentPage, total: widget.paths.length),
            ),
        ],
      ),
    ),
  );
}

class _PhotoCountIndicator extends StatelessWidget {
  const _PhotoCountIndicator({required this.currentPage, required this.total});
  final int currentPage;
  final int total;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(14)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      child: Text('${currentPage + 1}/$total', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
    ),
  );
}

