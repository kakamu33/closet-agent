import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/item_image.dart';
import '../../search/presentation/search_results_screen.dart';
import '../../shell/app_shell.dart';
import '../domain/wardrobe_tag.dart';
import 'item_detail_screen.dart';
import 'item_form_screen.dart';
import 'wardrobe_canvas_screen.dart';

class WardrobeScreen extends ConsumerStatefulWidget {
  const WardrobeScreen({super.key});
  @override
  ConsumerState<WardrobeScreen> createState() => _WardrobeScreenState();
}

class _WardrobeScreenState extends ConsumerState<WardrobeScreen> {
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
    if (shellTabIndex.value != 0 && _editingTags && mounted) {
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
    final tagState = ref.watch(wardrobeTagsProvider);
    final itemState = ref.watch(wardrobeItemsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的衣橱'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.tonalIcon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WardrobeCanvasScreen()),
              ),
              icon: const Icon(Icons.dashboard_customize_outlined, size: 19),
              label: const Text('线上衣柜'),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          _exitTagEditing();
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ItemFormScreen()),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('录入'),
      ),
      body: tagState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('标签加载失败：$error')),
        data: (tags) {
          final primary = tags.where((tag) => tag.isPrimary).toList();
          final details = _primaryId == null
              ? <WardrobeTag>[]
              : tags.where((tag) => tag.parentId == _primaryId).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
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
              _TagRow(
                tags: primary,
                selectedId: _primaryId,
                allLabel: '全部',
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
              const SizedBox(height: 8),
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
                        _DetailTags(
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
                        child: itemState.when(
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (error, _) => EmptyState(
                            icon: Icons.error_outline,
                            title: '衣橱加载失败',
                            message: '$error',
                          ),
                          data: (items) {
                            final visibleTagIds = _detailId != null
                                ? <String>{_detailId!}
                                : _primaryId == null
                                ? <String>{}
                                : <String>{
                                    _primaryId!,
                                    ...tags
                                        .where(
                                          (tag) => tag.parentId == _primaryId,
                                        )
                                        .map((tag) => tag.id),
                                  };
                            final filtered = items
                                .where(
                                  (item) =>
                                      (visibleTagIds.isEmpty ||
                                          item.tagIds.any(
                                            visibleTagIds.contains,
                                          )) &&
                                      true,
                                )
                                .toList();
                            if (items.isEmpty)
                              return EmptyState(
                                icon: Icons.checkroom_outlined,
                                title: '从第一件心爱单品开始',
                                message: '照片、标签与搭配都只保存在你的设备中。',
                                action: FilledButton.icon(
                                  onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const ItemFormScreen(),
                                    ),
                                  ),
                                  icon: const Icon(Icons.add),
                                  label: const Text('录入单品'),
                                ),
                              );
                            if (filtered.isEmpty)
                              return const EmptyState(
                                icon: Icons.search_off,
                                title: '没有找到单品',
                                message: '试试更换关键词或标签。',
                              );
                            return GridView.builder(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                4,
                                16,
                                100,
                              ),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    mainAxisSpacing: 12,
                                    crossAxisSpacing: 10,
                                    childAspectRatio: 1.02,
                                  ),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final item = filtered[index];
                                final tagNames = tags
                                    .where(
                                      (tag) => item.tagIds.contains(tag.id),
                                    )
                                    .map((tag) => tag.name)
                                    .join(' · ');
                                return Card(
                                  color: Colors.transparent,
                                  surfaceTintColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  clipBehavior: Clip.antiAlias,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: InkWell(
                                    hoverColor: Colors.transparent,
                                    splashColor: Colors.transparent,
                                    highlightColor: Colors.transparent,
                                    onTap: () {
                                      _exitTagEditing();
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              ItemDetailScreen(item: item),
                                        ),
                                      );
                                    },
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: SizedBox(
                                            width: double.infinity,
                                            child: ItemImage(
                                              path: item.imagePath,
                                              radius: 20,
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            12,
                                            11,
                                            12,
                                            3,
                                          ),
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
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            12,
                                            0,
                                            12,
                                            12,
                                          ),
                                          child: Text(
                                            tagNames.isEmpty
                                                ? '未分类'
                                                : tagNames,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
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
      await ref.read(wardrobeTagsProvider.notifier).reorder(reordered);
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
          maxLength: WardrobeTag.maxNameLength,
          decoration: InputDecoration(hintText: '标签名称（最多 ${WardrobeTag.maxNameLength} 个字符）'),
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
      if (tag == null) return;
      await _deleteTag(tag);
      return;
    }
    try {
      final existingTags = await ref.read(wardrobeTagsProvider.future);
      await ref
          .read(wardrobeTagsProvider.notifier)
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
          '删除“${tag.name}”会同时移除所有单品上的该标签标识。${tag.isPrimary ? '其下的细分标签也会被删除。' : ''}',
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
        await ref.read(wardrobeTagsProvider.notifier).remove(tag.id);
      } catch (error) {
        _showMessage('标签删除失败：$error');
      }
    }
  }
}

class _TagRow extends StatelessWidget {
  const _TagRow({
    required this.tags,
    required this.selectedId,
    required this.allLabel,
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
  final String allLabel;
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
        height: 48,
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: _ManagedChip(
                label: allLabel,
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
                      child: _ManagedChip(
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
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _ManagedChip(
            label: allLabel,
            selected: selectedId == null,
            onTap: () => onSelect(null),
          ),
          ...tags.map(
            (tag) => _ManagedChip(
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

class _DetailTags extends StatelessWidget {
  const _DetailTags({
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
      margin: const EdgeInsets.fromLTRB(10, 4, 0, 0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: editing || tags.isNotEmpty
          ? Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _ManagedChip(
                    label: '全部',
                    selected: selectedId == null,
                    vertical: true,
                    onTap: () => onSelect(null),
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
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
                          child: _ManagedChip(
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
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _ManagedChip(
                  label: '全部',
                  selected: selectedId == null,
                  vertical: true,
                  onTap: () => onSelect(null),
                ),
                ...tags.map(
                  (tag) => _ManagedChip(
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

class _FourCharacterLabel extends StatelessWidget {
  const _FourCharacterLabel({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const maxLineWidth = 8; // 一个汉字占 2 格；英文、数字和常见符号占 1 格。
    final lines = <String>[];
    var line = '';
    var width = 0;
    for (final rune in label.runes) {
      final character = String.fromCharCode(rune);
      final characterWidth = rune <= 0x7f ? 1 : 2;
      if (width + characterWidth > maxLineWidth && line.isNotEmpty) {
        lines.add(line);
        line = '';
        width = 0;
        if (lines.length == 2) break;
      }
      line += character;
      width += characterWidth;
    }
    if (line.isNotEmpty && lines.length < 2) lines.add(line);
    return Text(
      lines.join('\n'),
      maxLines: 2,
      textAlign: TextAlign.center,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color,
        fontSize: 12,
        height: 1.15,
        letterSpacing: 0,
      ),
    );
  }
}

class _ManagedChip extends StatelessWidget {
  const _ManagedChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.onDelete,
    this.vertical = false,
    this.editing = false,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDelete;
  final bool vertical;
  final bool editing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final chip = Material(
      color: selected ? colors.secondaryContainer : colors.surface,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? colors.secondary : colors.outlineVariant,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: vertical ? 6 : 14,
            vertical: vertical ? 6 : 8,
          ),
          child: SizedBox(
            width: vertical ? double.infinity : null,
            child: vertical
                ? _FourCharacterLabel(label: label, color: colors.onSurface)
                : Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.onSurface, fontSize: 13),
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
          chip,
          if (editing && onDelete != null)
            Positioned(
              right: -5,
              top: -5,
              child: InkResponse(
                onTap: onDelete,
                radius: 12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.error,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.surface, width: 1.5),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.close, size: 12, color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
