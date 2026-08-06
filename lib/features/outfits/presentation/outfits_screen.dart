import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/item_image.dart';
import '../../search/presentation/search_results_screen.dart';
import '../../shell/app_shell.dart';
import '../../wardrobe/domain/wardrobe_tag.dart';
import '../domain/outfit.dart';
import 'outfit_detail_screen.dart';
import 'outfit_form_screen.dart';

class OutfitsScreen extends ConsumerStatefulWidget {
  const OutfitsScreen({super.key});
  @override
  ConsumerState<OutfitsScreen> createState() => _OutfitsScreenState();
}

class _OutfitsScreenState extends ConsumerState<OutfitsScreen> {
  String? _primaryId;
  String? _detailId;
  bool _editingTags = false;

  @override
  void initState() {
    super.initState();
    shellTabIndex.addListener(_exitTagEditingWhenInactive);
  }

  @override
  void dispose() {
    shellTabIndex.removeListener(_exitTagEditingWhenInactive);
    super.dispose();
  }

  void _exitTagEditingWhenInactive() {
    if (shellTabIndex.value != 1 && _editingTags && mounted) {
      setState(() => _editingTags = false);
    }
  }

  void _exitTagEditing() {
    if (_editingTags) setState(() => _editingTags = false);
  }

  /// 进入标签编辑模式。
  ///
  /// 已经处于编辑状态时直接返回，不再调用 [setState]：这个方法会被
  /// [ReorderableListView] 的 `onReorderStart` 回调同步触发——即已经在
  /// 编辑态下，用户对某个标签“继续长按”会再次启动一次拖拽，若此时仍无
  /// 条件调用 setState，会在 ReorderableListView 内部正在处理拖拽启动的
  /// 构建过程中，强制要求祖先 Widget 重新构建，触发
  /// “setState() or markNeedsBuild() called during build” 异常并导致页面红屏。
  void _enterTagEditing() {
    if (!_editingTags) setState(() => _editingTags = true);
  }

  @override
  Widget build(BuildContext context) {
    final outfits = ref.watch(outfitsProvider);
    final tags = ref.watch(outfitTagsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('搭配灵感')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          _exitTagEditing();
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const OutfitFormScreen()),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('新搭配'),
      ),
      body: tags.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('标签加载失败：$error')),
        data: (allTags) {
          final primary = allTags.where((tag) => tag.isPrimary).toList();
          final details = _primaryId == null
              ? <WardrobeTag>[]
              : allTags.where((tag) => tag.parentId == _primaryId).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: SearchBar(
                  hintText: '搜索名称、标签、品牌、颜色或备注',
                  leading: const Icon(Icons.search),
                  onTap: () {
                    _exitTagEditing();
                    _openSearch('');
                  },
                  onSubmitted: (query) {
                    _exitTagEditing();
                    _openSearch(query);
                  },
                  trailing: [
                    IconButton(
                      onPressed: () {
                        _exitTagEditing();
                        _openSearch('');
                      },
                      icon: const Icon(Icons.arrow_forward),
                    ),
                  ],
                ),
              ),
              _TagBar(
                tags: primary,
                selectedId: _primaryId,
                onSelect: (id) => setState(() {
                  _primaryId = id;
                  _detailId = null;
                }),
                onAdd: () => _editTag(),
                onEdit: (tag) => _editTag(tag: tag),
                onDelete: _deleteTag,
                editing: _editingTags,
                onStartEditing: _enterTagEditing,
                onStartEditingTag: (_) => _enterTagEditing(),
                onReorder: (oldIndex, newIndex) =>
                    _reorderTags(primary, oldIndex, newIndex),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _editingTags
                      ? () => setState(() => _editingTags = false)
                      : null,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_primaryId != null)
                        _DetailTagBar(
                          tags: details,
                          selectedId: _detailId,
                          onSelect: (id) => setState(() => _detailId = id),
                          onAdd: () => _editTag(parentId: _primaryId),
                          onEdit: (tag) => _editTag(tag: tag),
                          onDelete: _deleteTag,
                          editing: _editingTags,
                          onStartEditing: _enterTagEditing,
                          onStartEditingTag: (_) => _enterTagEditing(),
                          onReorder: (oldIndex, newIndex) =>
                              _reorderTags(details, oldIndex, newIndex),
                        ),
                      Expanded(
                        child: outfits.when(
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (error, _) => EmptyState(
                            icon: Icons.error_outline,
                            title: '搭配加载失败',
                            message: '$error',
                          ),
                          data: (all) {
                            final visible = _detailId != null
                                ? <String>{_detailId!}
                                : _primaryId == null
                                ? <String>{}
                                : <String>{
                                    _primaryId!,
                                    ...allTags
                                        .where(
                                          (tag) => tag.parentId == _primaryId,
                                        )
                                        .map((tag) => tag.id),
                                  };
                            final shown = all.where((outfit) {
                              return visible.isEmpty ||
                                  outfit.tags.any(visible.contains);
                            }).toList();
                            if (all.isEmpty)
                              return EmptyState(
                                icon: Icons.auto_awesome_mosaic_outlined,
                                title: '收藏你的第一套搭配',
                                message: '组合已录入单品，也可以写下暂未录入的单品。',
                                action: FilledButton.icon(
                                  onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const OutfitFormScreen(),
                                    ),
                                  ),
                                  icon: const Icon(Icons.add),
                                  label: const Text('创建搭配'),
                                ),
                              );
                            if (shown.isEmpty)
                              return const EmptyState(
                                icon: Icons.filter_alt_off,
                                title: '没有符合条件的搭配',
                                message: '试试更换关键词或标签。',
                              );
                            return ListView.separated(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                10,
                                20,
                                100,
                              ),
                              itemCount: shown.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 14),
                              itemBuilder: (_, index) => _OutfitCard(
                                onTap: _exitTagEditing,
                                outfit: shown[index],
                                tagNames: allTags
                                    .where(
                                      (tag) =>
                                          shown[index].tags.contains(tag.id),
                                    )
                                    .map((tag) => tag.name)
                                    .toList(),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openSearch([String? query]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SearchResultsScreen(initialQuery: query?.trim() ?? ''),
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _reorderTags(
    List<WardrobeTag> tags,
    int oldIndex,
    int newIndex,
  ) async {
    final reordered = [...tags];
    if (newIndex > oldIndex) newIndex--;
    final tag = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, tag);
    try {
      await ref.read(outfitTagsProvider.notifier).reorder(reordered);
    } catch (error) {
      _showMessage('标签排序保存失败：$error');
    }
  }

  Future<void> _editTag({WardrobeTag? tag, String? parentId}) async {
    final text = TextEditingController(text: tag?.name ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tag == null ? '添加标签' : '编辑标签'),
        content: TextField(
          controller: text,
          autofocus: true,
          maxLength: 8,
          decoration: const InputDecoration(hintText: '标签名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, text.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    text.dispose();
    if (name == null) return;
    if (name.isEmpty) {
      if (tag != null) await _deleteTag(tag);
      return;
    }
    try {
      final existingTags = await ref.read(outfitTagsProvider.future);
      await ref
          .read(outfitTagsProvider.notifier)
          .save(
            WardrobeTag(
              id: tag?.id ?? const Uuid().v4(),
              name: name,
              parentId: tag?.parentId ?? parentId,
              sortOrder:
                  tag?.sortOrder ??
                  nextTagSortOrder(existingTags, parentId: parentId),
            ),
          );
    } on TagValidationException catch (error) {
      _showMessage(error.message);
    } catch (error) {
      _showMessage('标签保存失败：$error');
    }
  }

  Future<void> _deleteTag(WardrobeTag tag) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除标签？'),
        content: Text(
          '删除“${tag.name}”会同时移除所有搭配上的该标签标识。${tag.isPrimary ? '其下的细分标签也会被删除。' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      if (_primaryId == tag.id)
        setState(() {
          _primaryId = null;
          _detailId = null;
        });
      if (_detailId == tag.id) setState(() => _detailId = null);
      try {
        await ref.read(outfitTagsProvider.notifier).remove(tag.id);
      } catch (error) {
        _showMessage('标签删除失败：$error');
      }
    }
  }
}

class _TagBar extends StatelessWidget {
  const _TagBar({
    required this.tags,
    required this.selectedId,
    required this.onSelect,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.editing,
    required this.onStartEditing,
    required this.onStartEditingTag,
    required this.onReorder,
  });
  final List<WardrobeTag> tags;
  final String? selectedId;
  final ValueChanged<String?> onSelect;
  final VoidCallback onAdd;
  final ValueChanged<WardrobeTag> onEdit;
  final ValueChanged<WardrobeTag> onDelete;
  final bool editing;
  final VoidCallback onStartEditing;
  final ValueChanged<WardrobeTag> onStartEditingTag;
  final ReorderCallback onReorder;
  @override
  Widget build(BuildContext context) {
    if (editing || tags.isNotEmpty)
      return SizedBox(
        height: 44,
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: _TagChip(
                label: '全部',
                selected: selectedId == null,
                onTap: () => onSelect(null),
              ),
            ),
            Expanded(
              child: ReorderableListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: tags.length,
                onReorder: onReorder,
                onReorderStart: (_) => onStartEditing(),
                buildDefaultDragHandles: false,
                proxyDecorator: (child, index, animation) => child,
                itemBuilder: (context, index) {
                  final tag = tags[index];
                  return ReorderableDelayedDragStartListener(
                    key: ValueKey(tag.id),
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 3,
                      ),
                      child: _TagChip(
                        label: tag.name,
                        selected: selectedId == tag.id,
                        editing: editing,
                        onTap: () => editing ? onEdit(tag) : onSelect(tag.id),
                        onDelete: () => onDelete(tag),
                      ),
                    ),
                  );
                },
              ),
            ),
            IgnorePointer(
              ignoring: editing,
              child: Opacity(
                opacity: editing ? 0 : 1,
                child: IconButton(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: '添加标签',
                ),
              ),
            ),
          ],
        ),
      );
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _TagChip(
            label: '全部',
            selected: selectedId == null,
            onTap: () => onSelect(null),
          ),
          ...tags.map(
            (tag) => _TagChip(
              label: tag.name,
              selected: selectedId == tag.id,
              onTap: () => onSelect(tag.id),
              onLongPress: () => onStartEditingTag(tag),
              onDelete: () => onDelete(tag),
            ),
          ),
          IconButton(
            onPressed: onAdd,
            icon: const Icon(Icons.add_circle_outline),
            tooltip: '添加标签',
          ),
        ],
      ),
    );
  }
}

class _DetailTagBar extends StatelessWidget {
  const _DetailTagBar({
    required this.tags,
    required this.selectedId,
    required this.onSelect,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.editing,
    required this.onStartEditing,
    required this.onStartEditingTag,
    required this.onReorder,
  });
  final List<WardrobeTag> tags;
  final String? selectedId;
  final ValueChanged<String?> onSelect;
  final VoidCallback onAdd;
  final ValueChanged<WardrobeTag> onEdit;
  final ValueChanged<WardrobeTag> onDelete;
  final bool editing;
  final VoidCallback onStartEditing;
  final ValueChanged<WardrobeTag> onStartEditingTag;
  final ReorderCallback onReorder;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 104,
    height: 360,
    child: Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 0, 100),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: editing || tags.isNotEmpty
          ? Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _TagChip(
                    label: '全部',
                    selected: selectedId == null,
                    vertical: true,
                    onTap: () => onSelect(null),
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    itemCount: tags.length,
                    onReorder: onReorder,
                    onReorderStart: (_) => onStartEditing(),
                    buildDefaultDragHandles: false,
                    proxyDecorator: (child, index, animation) => child,
                    itemBuilder: (context, index) {
                      final tag = tags[index];
                      return ReorderableDelayedDragStartListener(
                        key: ValueKey(tag.id),
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          child: _TagChip(
                            label: tag.name,
                            selected: selectedId == tag.id,
                            vertical: true,
                            editing: editing,
                            onTap: () =>
                                editing ? onEdit(tag) : onSelect(tag.id),
                            onDelete: () => onDelete(tag),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                IgnorePointer(
                  ignoring: editing,
                  child: Opacity(
                    opacity: editing ? 0 : 1,
                    child: IconButton(
                      onPressed: onAdd,
                      icon: const Icon(Icons.add, size: 20),
                      tooltip: '添加细分标签',
                    ),
                  ),
                ),
              ],
            )
          : ListView(
              children: [
                _TagChip(
                  label: '全部',
                  selected: selectedId == null,
                  vertical: true,
                  onTap: () => onSelect(null),
                ),
                ...tags.map(
                  (tag) => _TagChip(
                    label: tag.name,
                    selected: selectedId == tag.id,
                    vertical: true,
                    onTap: () => onSelect(tag.id),
                    onLongPress: () => onStartEditingTag(tag),
                    onDelete: () => onDelete(tag),
                  ),
                ),
                IconButton(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 20),
                  tooltip: '添加细分标签',
                ),
              ],
            ),
    ),
  );
}

class _EditModeDragListener extends StatefulWidget {
  const _EditModeDragListener({
    required this.onEnterEditMode,
    required this.child,
  });

  final VoidCallback onEnterEditMode;
  final Widget child;

  @override
  State<_EditModeDragListener> createState() => _EditModeDragListenerState();
}

class _EditModeDragListenerState extends State<_EditModeDragListener> {
  Timer? _timer;
  Offset? _downPosition;

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _cancelTimer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) {
      _downPosition = event.position;
      _cancelTimer();
      _timer = Timer(const Duration(milliseconds: 320), widget.onEnterEditMode);
    },
    onPointerMove: (event) {
      if (_downPosition != null &&
          (event.position - _downPosition!).distance > 18) {
        _cancelTimer();
      }
    },
    onPointerUp: (_) => _cancelTimer(),
    onPointerCancel: (_) => _cancelTimer(),
    child: widget.child,
  );
}

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.onDelete,
    this.editing = false,
    this.vertical = false,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDelete;
  final bool editing;
  final bool vertical;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const radius = 10.0;
    final button = Material(
      color: selected ? colors.secondaryContainer : colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(
          color: selected ? colors.secondary : colors.outlineVariant,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(radius),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: vertical ? 6 : 14,
            vertical: vertical ? 6 : 8,
          ),
          child: SizedBox(
            width: vertical ? double.infinity : null,
            child: Text(
              label,
              maxLines: vertical ? 2 : 1,
              textAlign: vertical ? TextAlign.center : TextAlign.start,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: vertical ? 12 : 13),
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: vertical ? 7 : 4, vertical: 3),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          button,
          if (editing && onDelete != null)
            Positioned(
              right: -3,
              top: -3,
              child: InkResponse(
                onTap: onDelete,
                radius: 10,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.error,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 12, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OutfitCard extends StatelessWidget {
  const _OutfitCard({
    required this.outfit,
    required this.tagNames,
    required this.onTap,
  });
  final Outfit outfit;
  final VoidCallback onTap;
  final List<String> tagNames;
  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(24),
    onTap: () {
      onTap();
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => OutfitDetailScreen(outfit: outfit)),
      );
    },
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
                    child: const Icon(Icons.auto_awesome, color: Colors.white),
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
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    [...tagNames, '${outfit.entries.length}件'].join(' · '),
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
}
