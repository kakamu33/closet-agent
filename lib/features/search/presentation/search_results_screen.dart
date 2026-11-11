import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/item_image.dart';
import '../../outfits/domain/outfit.dart';
import '../../outfits/presentation/outfit_detail_screen.dart';
import '../../wardrobe/domain/wardrobe_item.dart';
import '../../wardrobe/presentation/item_detail_screen.dart';
import '../domain/search_service.dart';

class SearchResultsScreen extends ConsumerStatefulWidget {
  const SearchResultsScreen({super.key, required this.initialQuery});
  final String initialQuery;

  @override
  ConsumerState<SearchResultsScreen> createState() =>
      _SearchResultsScreenState();
}

class _SearchResultsScreenState extends ConsumerState<SearchResultsScreen> {
  late final TextEditingController _controller;
  late String _query;
  var _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery;
    _controller = TextEditingController(text: _query);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final items =
        ref.watch(wardrobeItemsProvider).value ?? const <WardrobeItem>[];
    final outfits = ref.watch(outfitsProvider).value ?? const <Outfit>[];
    final wardrobeTags = ref.watch(wardrobeTagsProvider).value ?? const [];
    final outfitTags = ref.watch(outfitTagsProvider).value ?? const [];
    final result = SearchService.search(
      query: _query,
      items: items,
      outfits: outfits,
      wardrobeTags: wardrobeTags,
      outfitTags: outfitTags,
    );
    final isEmpty = _query.trim().isEmpty;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest.withValues(
                          alpha: .55,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: colors.outlineVariant.withValues(alpha: .55),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Row(
                        children: [
                          const SizedBox(width: 15),
                          Icon(
                            Icons.search_rounded,
                            color: colors.primary,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Theme(
                              data: Theme.of(context).copyWith(
                                inputDecorationTheme:
                                    const InputDecorationTheme(
                                      filled: false,
                                      fillColor: Colors.transparent,
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      contentPadding: EdgeInsets.zero,
                                      isDense: true,
                                    ),
                              ),
                              child: TextField(
                                controller: _controller,
                                autofocus: true,
                                textInputAction: TextInputAction.search,
                                decoration: const InputDecoration(
                                  hintText: '搜索名称、标签、品牌、颜色或备注',
                                ),
                                onChanged: (value) =>
                                    setState(() => _query = value),
                              ),
                            ),
                          ),
                          if (!isEmpty)
                            IconButton(
                              tooltip: '清空',
                              onPressed: () {
                                _controller.clear();
                                setState(() => _query = '');
                              },
                              icon: const Icon(Icons.cancel_rounded, size: 19),
                            ),
                          const SizedBox(width: 3),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (!isEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '“${_query.trim()}” 的搜索结果',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest.withValues(alpha: .5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      _SearchSegment(
                        label: '衣物',
                        count: result.items.length,
                        selected: _selectedTab == 0,
                        onTap: () => setState(() => _selectedTab = 0),
                      ),
                      _SearchSegment(
                        label: '搭配',
                        count: result.outfits.length,
                        selected: _selectedTab == 1,
                        onTap: () => setState(() => _selectedTab = 1),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
            ],
            Expanded(
              child: isEmpty
                  ? const EmptyState(
                      icon: Icons.manage_search_rounded,
                      title: '搜索你的衣橱',
                      message: '可查找名称、标签、品牌、颜色与备注。',
                    )
                  : _selectedTab == 0
                  ? _ItemResults(items: result.items)
                  : _OutfitResults(
                      outfits: result.outfits,
                      tagNames: {
                        for (final tag in outfitTags) tag.id: tag.name,
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchSegment extends StatelessWidget {
  const _SearchSegment({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Expanded(
      child: Material(
        color: selected ? colors.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? colors.primary : colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 6),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: selected
                        ? colors.primaryContainer
                        : colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 12,
                        color: selected
                            ? colors.onPrimaryContainer
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ItemResults extends StatelessWidget {
  const _ItemResults({required this.items});
  final List<WardrobeItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off,
        title: '未找到衣物',
        message: '试试更换关键词。',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 10,
        childAspectRatio: 1.02,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ItemDetailScreen(item: item)),
          ),
          child: Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SizedBox(
                    width: double.infinity,
                    child: ItemImage(path: item.imagePath, radius: 20),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
                  child: Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OutfitResults extends StatelessWidget {
  const _OutfitResults({required this.outfits, required this.tagNames});
  final List<Outfit> outfits;
  final Map<String, String> tagNames;

  @override
  Widget build(BuildContext context) {
    if (outfits.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off,
        title: '未找到搭配',
        message: '试试更换关键词。',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      itemCount: outfits.length,
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final outfit = outfits[index];
        final labels = outfit.tags
            .map((id) => tagNames[id])
            .whereType<String>();
        return InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => OutfitDetailScreen(outfit: outfit),
            ),
          ),
          child: Card(
            child: Row(
              children: [
                SizedBox(
                  width: 108,
                  height: 128,
                  child: outfit.photos.isEmpty
                      ? Container(
                          decoration: const BoxDecoration(
                            borderRadius: BorderRadius.horizontal(
                              left: Radius.circular(20),
                            ),
                            gradient: LinearGradient(
                              colors: [Color(0xFFE4D8CC), Color(0xFFB1B8AA)],
                            ),
                          ),
                          child: const Icon(
                            Icons.auto_awesome,
                            color: Colors.white,
                          ),
                        )
                      : ItemImage(
                          path: outfit.photos.first,
                          width: 108,
                          height: 128,
                          radius: 0,
                        ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          outfit.name,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          [...labels, '${outfit.entries.length}件'].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
