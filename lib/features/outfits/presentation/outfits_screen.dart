import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/widgets/category_picker.dart';
import '../../../core/widgets/record_selection.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/item_image.dart';
import '../../search/presentation/search_results_screen.dart';
import '../../shell/app_shell.dart';
import '../../wardrobe/domain/wardrobe_tag.dart';
import '../domain/outfit.dart';
import 'outfit_detail_screen.dart';
import 'outfit_form_screen.dart';
import '../../assistant/presentation/assistant_screen.dart';

class OutfitsScreen extends ConsumerStatefulWidget {
  const OutfitsScreen({super.key});
  @override
  ConsumerState<OutfitsScreen> createState() => _OutfitsScreenState();
}

class _OutfitsScreenState extends ConsumerState<OutfitsScreen> {
  String? _primaryId;
  String? _detailId;
  bool _editingTags = false;
  bool _selecting = false;
  bool _bulkBusy = false;
  String? _bulkError;
  final _selectedRecords = <String>{};
  Set<String> _visibleRecords = {};

  void _cancelSelection() => setState(() {
    _selecting = false;
    _selectedRecords.clear();
    _bulkError = null;
  });
  void _toggleRecord(String id) {
    if (_bulkBusy) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..removeCurrentSnackBar();
    setState(() {
      _bulkError = null;
      _selecting = true;
      _editingTags = false;
      _selectedRecords.contains(id)
          ? _selectedRecords.remove(id)
          : _selectedRecords.add(id);
    });
  }

  Future<void> _bulkAction(bool moving) async {
    if (_bulkBusy || _selectedRecords.isEmpty) return;
    final owner = ref.read(authSessionProvider).value?.id;
    final controller = ref.read(outfitsProvider.notifier);
    final ids = Set<String>.of(_selectedRecords);
    List<String>? target;
    if (moving) {
      target = await showCategoryPicker(
        context,
        [],
        outfits: true,
        moving: true,
      );
      if (target == null) return;
    } else if (!await confirmRecordDeletion(
      context,
      ids.length,
      outfits: true,
    )) {
      return;
    }
    if (!mounted || ref.read(authSessionProvider).value?.id != owner) return;
    setState(() {
      _bulkBusy = true;
      _bulkError = null;
    });
    try {
      if (moving) {
        await controller.moveMany(ids, target!);
      } else {
        await controller.removeMany(ids);
      }
      if (mounted && ref.read(authSessionProvider).value?.id == owner) {
        _cancelSelection();
      }
    } catch (error) {
      if (mounted && ref.read(authSessionProvider).value?.id == owner) {
        setState(() => _bulkError = '部分操作未完成，可重试：$error');
      }
    } finally {
      if (mounted && ref.read(authSessionProvider).value?.id == owner) {
        setState(() => _bulkBusy = false);
      }
    }
  }

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
    if (shellTabIndex.value != 1 && (_editingTags || _selecting) && mounted) {
      setState(() {
        _editingTags = false;
        _selecting = false;
        _selectedRecords.clear();
      });
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
    ref.listen(authSessionProvider.select((session) => session.value?.id), (
      old,
      current,
    ) {
      if (old != current) {
        setState(() {
          _selecting = false;
          _bulkBusy = false;
          _selectedRecords.clear();
        });
      }
    });

    final outfits = ref.watch(outfitsProvider);
    final tags = ref.watch(outfitTagsProvider);
    final showsEmpty =
        tags.asData != null &&
        !tags.isLoading &&
        !tags.hasError &&
        outfits.asData?.value.isEmpty == true &&
        !outfits.isLoading &&
        !outfits.hasError;
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selecting && !_bulkBusy) _cancelSelection();
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 18,
          title: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _OutfitLogo(),
              SizedBox(width: 9),
              Text(
                '搭配',
                style: TextStyle(
                  fontFamily: 'LXGWWenKai',
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF5C3A20),
                  letterSpacing: .4,
                ),
              ),
            ],
          ),
          actions: [
            if (!_selecting)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton.icon(
                  onPressed: _openStylistPreview,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF6F6257),
                    minimumSize: const Size(48, 44),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                  icon: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFCDBDAA)),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Text(
                      'AI',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  label: const Text('帮我搭配'),
                ),
              ),
          ],
        ),
        bottomNavigationBar: _selecting
            ? RecordSelectionBar(
                count: _selectedRecords.length,
                message: _bulkError,
                busy: _bulkBusy,
                onAll: () =>
                    setState(() => _selectedRecords.addAll(_visibleRecords)),
                onCancel: _cancelSelection,
                onMove: () => _bulkAction(true),
                onDelete: () => _bulkAction(false),
              )
            : null,
        floatingActionButton: _selecting || showsEmpty
            ? null
            : FloatingActionButton.extended(
                heroTag: 'outfit-add',
                onPressed: _openNewOutfit,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                icon: const Icon(Icons.add, size: 20),
                label: const Text('新搭配', style: TextStyle(fontSize: 14)),
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
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFCFBF8),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFE5E0D9),
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: TextField(
                        textAlignVertical: TextAlignVertical.center,
                        style: const TextStyle(
                          fontFamily: 'SourceHanSansCN',
                          fontSize: 14,
                          color: Color(0xFF382C20),
                        ),
                        decoration: const InputDecoration(
                          filled: false,
                          fillColor: Colors.transparent,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          isDense: true,
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            color: Color(0xFF796F65),
                            size: 18,
                          ),
                          prefixIconConstraints: BoxConstraints(
                            minWidth: 40,
                            minHeight: 44,
                          ),
                          hintText: '搜索搭配名称、标签',
                          hintStyle: TextStyle(
                            fontFamily: 'SourceHanSansCN',
                            fontSize: 14,
                            color: Color(0xFF796F65),
                          ),
                          contentPadding: EdgeInsets.symmetric(vertical: 11),
                        ),
                        readOnly: true,
                        onTap: () {
                          _exitTagEditing();
                          _openSearch('');
                        },
                        onSubmitted: (query) {
                          _exitTagEditing();
                          _openSearch(query);
                        },
                      ),
                    ),
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
                            loading: () => const Center(
                              child: CircularProgressIndicator(),
                            ),
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
                              _visibleRecords = shown
                                  .map((outfit) => outfit.id)
                                  .toSet();
                              if (all.isEmpty) {
                                return EmptyState(
                                  icon: Icons.view_quilt_outlined,
                                  title: '留下你喜欢的穿搭',
                                  message: '组合衣橱里的单品，保存成一套随时可用的搭配。',
                                  action: FilledButton.icon(
                                    onPressed: _openNewOutfit,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF805A3B),
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(0, 48),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      textStyle: const TextStyle(fontSize: 14),
                                    ),
                                    icon: const Icon(Icons.add, size: 18),
                                    label: const Text('创建第一套搭配'),
                                  ),
                                );
                              }
                              if (shown.isEmpty) {
                                return const EmptyState(
                                  icon: Icons.filter_alt_off,
                                  title: '没有符合条件的搭配',
                                  message: '切换分类查看，或创建一套新的搭配。',
                                );
                              }
                              return ListView.separated(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  4,
                                  20,
                                  96,
                                ),
                                itemCount: shown.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (_, index) => SelectableRecord(
                                  selecting: _selecting,
                                  selected: _selectedRecords.contains(
                                    shown[index].id,
                                  ),
                                  onEnter: () => _toggleRecord(shown[index].id),
                                  onToggle: () =>
                                      _toggleRecord(shown[index].id),
                                  child: _OutfitCard(
                                    onTap: _exitTagEditing,
                                    outfit: shown[index],
                                    tagNames: allTags
                                        .where(
                                          (tag) => shown[index].tags.contains(
                                            tag.id,
                                          ),
                                        )
                                        .map((tag) => tag.name)
                                        .toList(),
                                  ),
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
      ),
    );
  }

  void _openNewOutfit() {
    _exitTagEditing();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const OutfitFormScreen()),
    );
  }

  void _openStylistPreview() {
    _exitTagEditing();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AssistantScreen()),
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
    final tag = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, tag);
    try {
      await ref.read(outfitTagsProvider.notifier).reorder(reordered);
    } catch (error) {
      _showMessage('标签排序保存失败：$error');
    }
  }

  Future<void> _editTag({WardrobeTag? tag, String? parentId}) async {
    await showCategoryEditor(
      context,
      outfits: true,
      tag: tag,
      parentId: parentId,
    );
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
      if (_primaryId == tag.id) {
        setState(() {
          _primaryId = null;
          _detailId = null;
        });
      }
      if (_detailId == tag.id) setState(() => _detailId = null);
      try {
        await ref.read(outfitTagsProvider.notifier).remove(tag.id);
      } catch (error) {
        _showMessage('标签删除失败：$error');
      }
    }
  }
}

class _OutfitLogo extends StatelessWidget {
  const _OutfitLogo();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 30,
    height: 30,
    child: Icon(Icons.view_quilt_outlined, color: Color(0xFF9A7546), size: 21),
  );
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
    if (editing || tags.isNotEmpty) {
      return SizedBox(
        height: 48,
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
                onReorderItem: onReorder,
                onReorderStart: (_) => onStartEditing(),
                buildDefaultDragHandles: false,
                proxyDecorator: (child, index, animation) => Material(
                  color: Colors.transparent,
                  elevation: 0,
                  child: IgnorePointer(child: child),
                ),
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
                child: _AddCategoryButton(onPressed: onAdd),
              ),
            ),
          ],
        ),
      );
    }
    return SizedBox(
      height: 48,
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
          _AddCategoryButton(onPressed: onAdd),
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
      margin: const EdgeInsets.fromLTRB(10, 4, 0, 0),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
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
              footer: IgnorePointer(
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
              itemCount: tags.length,
              onReorderItem: onReorder,
              onReorderStart: (_) => onStartEditing(),
              buildDefaultDragHandles: false,
              proxyDecorator: (child, index, animation) => Material(
                color: Colors.transparent,
                elevation: 0,
                child: IgnorePointer(child: child),
              ),
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
                      onTap: () => editing ? onEdit(tag) : onSelect(tag.id),
                      onDelete: () => onDelete(tag),
                    ),
                  ),
                );
              },
            ),
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
    final radius = vertical ? 12.0 : 22.0;
    const selectedBackground = Color(0xFFEAE2D7);
    const unselectedBackground = Color(0xFFF7F5F1);
    const selectedText = Color(0xFF5C3A20);
    const unselectedText = Color(0xFF77736D);
    final button = Material(
      color: selected ? selectedBackground : unselectedBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(radius),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: vertical ? 6 : 14,
            vertical: 6,
          ),
          child: SizedBox(
            width: vertical ? double.infinity : null,
            child: Text(
              label,
              maxLines: vertical ? 2 : 1,
              textAlign: vertical ? TextAlign.center : TextAlign.start,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: vertical ? 12 : 13,
                color: selected ? selectedText : unselectedText,
              ),
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

class _AddCategoryButton extends StatelessWidget {
  const _AddCategoryButton({required this.onPressed});
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      foregroundColor: const Color(0xFF817A72),
      minimumSize: const Size(48, 44),
      textStyle: const TextStyle(fontSize: 13),
    ),
    icon: const Icon(Icons.add, size: 16),
    label: const Text('添加分类'),
  );
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
  Widget build(BuildContext context) {
    final entryImages = outfit.entries
        .map((entry) => entry.imagePath)
        .whereType<String>()
        .take(4)
        .toList();
    return Material(
      color: const Color(0xFFFCFBF8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFEAE5DE)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          onTap();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => OutfitDetailScreen(outfit: outfit),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              SizedBox(
                width: 88,
                height: 100,
                child: outfit.photos.isNotEmpty
                    ? ItemImage(
                        path: outfit.photos.first,
                        radius: 8,
                        backgroundColor: Colors.white,
                      )
                    : entryImages.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: GridView.count(
                          physics: const NeverScrollableScrollPhysics(),
                          padding: EdgeInsets.zero,
                          crossAxisCount: entryImages.length == 1 ? 1 : 2,
                          childAspectRatio: entryImages.length == 1
                              ? .88
                              : entryImages.length <= 2
                              ? .44
                              : .88,
                          children: [
                            for (final path in entryImages)
                              ItemImage(
                                path: path,
                                radius: 0,
                                backgroundColor: Colors.white,
                              ),
                          ],
                        ),
                      )
                    : const ItemImage(
                        radius: 8,
                        backgroundColor: Color(0xFFF0EEEA),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      outfit.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2D2C29),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      ['${outfit.entries.length} 件单品', ...tagNames].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF807B74),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: Color(0xFFABA298),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
