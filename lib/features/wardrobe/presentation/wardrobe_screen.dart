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

enum _WardrobeSort { newest, oldest, name }

class _WardrobeScreenState extends ConsumerState<WardrobeScreen> {
  String? _primaryId;
  String? _detailId;
  bool _editingTags = false;
  _WardrobeSort _sort = _WardrobeSort.newest;

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
    // Hide the FAB only when the alternative recording CTA can be rendered.
    final showsEmptyWardrobe =
        tagState.asData != null &&
        !tagState.isLoading &&
        !tagState.hasError &&
        itemState.asData?.value.isEmpty == true &&
        !itemState.isLoading &&
        !itemState.hasError;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 18,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _WardrobeLogo(),
            SizedBox(width: 9),
            Text(
              '衣橱',
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
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF6F6257),
                minimumSize: const Size(48, 44),
                textStyle: const TextStyle(fontSize: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
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
      floatingActionButton: showsEmptyWardrobe
          ? null
          : FloatingActionButton.extended(
              heroTag: 'wardrobe-add',
              onPressed: _openNewItem,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              icon: const Icon(Icons.add, size: 20),
              label: const Text('录入', style: TextStyle(fontSize: 14)),
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
                        hintText: '搜索名称、标签、颜色',
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
                            if (items.isEmpty) {
                              return EmptyState(
                                icon: Icons.checkroom_outlined,
                                illustration: const _WardrobeIllustration(),
                                title: '把第一件衣服放进衣橱',
                                message: '拍照或从相册选择，建立你的单品记录。',
                                action: FilledButton.icon(
                                  onPressed: _openNewItem,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF805A3B),
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(0, 48),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 12,
                                    ),
                                    textStyle: const TextStyle(fontSize: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  icon: const Icon(Icons.add, size: 18),
                                  label: const Text('添加第一件衣物'),
                                ),
                              );
                            }
                            if (filtered.isEmpty) {
                              return const EmptyState(
                                icon: Icons.search_off,
                                title: '这个分类还没有衣物',
                                message: '添加衣物时选择此分类，或切换分类查看。',
                              );
                            }
                            filtered.sort((a, b) {
                              final result = switch (_sort) {
                                _WardrobeSort.newest => b.createdAt.compareTo(
                                  a.createdAt,
                                ),
                                _WardrobeSort.oldest => a.createdAt.compareTo(
                                  b.createdAt,
                                ),
                                _WardrobeSort.name => a.name.compareTo(b.name),
                              };
                              return result == 0
                                  ? a.id.compareTo(b.id)
                                  : result;
                            });
                            return Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    0,
                                    12,
                                    4,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '共 ${filtered.length} 件',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF807B74),
                                          ),
                                        ),
                                      ),
                                      PopupMenuButton<_WardrobeSort>(
                                        tooltip: '排序',
                                        position: PopupMenuPosition.under,
                                        offset: const Offset(0, 4),
                                        color: const Color(0xFFFCFBF8),
                                        surfaceTintColor: Colors.transparent,
                                        shadowColor: const Color(0x24000000),
                                        elevation: 4,
                                        constraints:
                                            const BoxConstraints.tightFor(
                                              width: 148,
                                            ),
                                        menuPadding: const EdgeInsets.symmetric(
                                          vertical: 4,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          side: const BorderSide(
                                            color: Color(0xFFE7E2DA),
                                          ),
                                        ),
                                        onSelected: (value) =>
                                            setState(() => _sort = value),
                                        itemBuilder: (_) => [
                                          for (final value
                                              in _WardrobeSort.values)
                                            PopupMenuItem(
                                              value: value,
                                              height: 44,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 14,
                                                  ),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      _sortLabel(value),
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        fontWeight:
                                                            _sort == value
                                                            ? FontWeight.w500
                                                            : FontWeight.w400,
                                                        color: const Color(
                                                          0xFF514A42,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  if (_sort == value)
                                                    const Icon(
                                                      Icons.check_rounded,
                                                      size: 16,
                                                      color: Color(0xFF805A3B),
                                                    ),
                                                ],
                                              ),
                                            ),
                                        ],
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                _sortLabel(_sort),
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Color(0xFF68635D),
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              const Icon(
                                                Icons
                                                    .keyboard_arrow_down_rounded,
                                                size: 16,
                                                color: Color(0xFF807B74),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      final columns = constraints.maxWidth < 280
                                          ? 1
                                          : (constraints.maxWidth / 200)
                                                .floor()
                                                .clamp(2, 6);
                                      final cardWidth =
                                          (constraints.maxWidth -
                                              40 -
                                              (columns - 1) * 12) /
                                          columns;
                                      // Square photos retain the original collection density.
                                      final textScale = MediaQuery.textScalerOf(
                                        context,
                                      ).scale(1);
                                      return GridView.builder(
                                        padding: const EdgeInsets.fromLTRB(
                                          20,
                                          0,
                                          20,
                                          96,
                                        ),
                                        gridDelegate:
                                            SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount: columns,
                                              mainAxisSpacing: 20,
                                              crossAxisSpacing: 12,
                                              mainAxisExtent:
                                                  cardWidth + 60 * textScale,
                                            ),
                                        itemCount: filtered.length,
                                        itemBuilder: (context, index) {
                                          final item = filtered[index];
                                          final tagNames = tags
                                              .where(
                                                (tag) => item.tagIds.contains(
                                                  tag.id,
                                                ),
                                              )
                                              .map((tag) => tag.name)
                                              .join(' · ');
                                          return Material(
                                            color: Colors.transparent,
                                            child: InkWell(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              onTap: () {
                                                _exitTagEditing();
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        ItemDetailScreen(
                                                          item: item,
                                                        ),
                                                  ),
                                                );
                                              },
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  AspectRatio(
                                                    aspectRatio: 1,
                                                    child: ItemImage(
                                                      path: item.imagePath,
                                                      radius: 12,
                                                      fit: BoxFit.cover,
                                                      backgroundColor:
                                                          Colors.white,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 10),
                                                  Text(
                                                    item.name,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: Color(0xFF2D2C29),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 3),
                                                  Text(
                                                    tagNames.isEmpty
                                                        ? '未分类'
                                                        : tagNames,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Color(0xFF807B74),
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

  String _sortLabel(_WardrobeSort value) => switch (value) {
    _WardrobeSort.newest => '最近添加',
    _WardrobeSort.oldest => '最早添加',
    _WardrobeSort.name => '名称排序',
  };

  void _openNewItem() {
    _exitTagEditing();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ItemFormScreen()),
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
      await ref.read(wardrobeTagsProvider.notifier).reorder(reordered);
    } catch (error) {
      _showMessage('标签排序保存失败：$error');
    }
  }

  Future<void> _editTag({WardrobeTag? tag, String? parentId}) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _TagNameDialog(tag: tag),
    );
    if (!mounted || name == null) return;
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
              syncVersion: tag?.syncVersion ?? 0,
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
      if (_primaryId == tag.id) {
        setState(() {
          _primaryId = null;
          _detailId = null;
        });
      }
      if (_detailId == tag.id) setState(() => _detailId = null);
      try {
        await ref.read(wardrobeTagsProvider.notifier).remove(tag.id);
      } catch (error) {
        _showMessage('标签删除失败：$error');
      }
    }
  }
}

class _TagNameDialog extends StatefulWidget {
  const _TagNameDialog({this.tag});

  final WardrobeTag? tag;

  @override
  State<_TagNameDialog> createState() => _TagNameDialogState();
}

class _TagNameDialogState extends State<_TagNameDialog> {
  late final _text = TextEditingController(text: widget.tag?.name ?? '');

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.tag == null ? '添加标签' : '编辑标签'),
    content: TextField(
      controller: _text,
      autofocus: true,
      maxLength: WardrobeTag.maxNameLength,
      decoration: InputDecoration(
        hintText: '标签名称（最多 ${WardrobeTag.maxNameLength} 个字符）',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _text.text.trim()),
        child: const Text('保存'),
      ),
    ],
  );
}

class _WardrobeLogo extends StatelessWidget {
  const _WardrobeLogo();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 30,
    height: 30,
    child: const Icon(
      Icons.checkroom_rounded,
      color: Color(0xFF9A7546),
      size: 21,
    ),
  );
}

class _WardrobeIllustration extends StatelessWidget {
  const _WardrobeIllustration();

  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
    child: SizedBox(
      width: 84,
      height: 72,
      child: CustomPaint(painter: _WardrobeIllustrationPainter()),
    ),
  );
}

class _WardrobeIllustrationPainter extends CustomPainter {
  const _WardrobeIllustrationPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 112, size.height / 96);
    final stroke = Paint()
      ..color = const Color(0xFF9A8672)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = const Color(0xFFEDE5DA);
    const cabinet = Rect.fromLTWH(12, 6, 88, 78);
    canvas.drawRRect(
      RRect.fromRectAndRadius(cabinet, const Radius.circular(4)),
      Paint()..color = const Color(0xFFF1EBE2),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(cabinet, const Radius.circular(4)),
      stroke,
    );
    canvas.drawLine(const Offset(22, 21), const Offset(90, 21), stroke);
    // A shirt and folded knitwear, rather than another standalone hanger.
    final shirt = Path()
      ..moveTo(45, 31)
      ..lineTo(39, 28)
      ..lineTo(28, 36)
      ..lineTo(33, 45)
      ..lineTo(38, 42)
      ..lineTo(38, 63)
      ..lineTo(62, 63)
      ..lineTo(62, 42)
      ..lineTo(67, 45)
      ..lineTo(72, 36)
      ..lineTo(61, 28)
      ..lineTo(55, 31)
      ..quadraticBezierTo(50, 37, 45, 31)
      ..close();
    canvas.drawPath(shirt, fill);
    canvas.drawPath(shirt, stroke);
    canvas.drawLine(const Offset(50, 22), const Offset(50, 27), stroke);
    canvas.drawLine(const Offset(22, 72), const Offset(90, 72), stroke);
    final folded = RRect.fromRectAndRadius(
      const Rect.fromLTWH(72, 60, 15, 6),
      const Radius.circular(2),
    );
    canvas.drawRRect(folded, fill);
    canvas.drawRRect(folded, stroke);
    canvas.drawLine(const Offset(73, 69), const Offset(87, 69), stroke);
    canvas.drawLine(const Offset(20, 84), const Offset(20, 90), stroke);
    canvas.drawLine(const Offset(92, 84), const Offset(92, 90), stroke);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WardrobeIllustrationPainter oldDelegate) =>
      false;
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
    if (editing || tags.isNotEmpty) {
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
                child: TextButton.icon(
                  onPressed: onAdd,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF817A72),
                    minimumSize: const Size(48, 44),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('添加分类'),
                ),
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
          TextButton.icon(
            onPressed: onAdd,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF817A72),
              minimumSize: const Size(48, 44),
              textStyle: const TextStyle(fontSize: 13),
            ),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('添加分类'),
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
    const selectedBackground = Color(0xFFEAE2D7);
    const unselectedBackground = Color(0xFFF7F5F1);
    const selectedText = Color(0xFF5C3A20);
    const unselectedText = Color(0xFF77736D);
    final chip = Material(
      color: selected ? selectedBackground : unselectedBackground,
      shape: vertical
          ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
          : const StadiumBorder(),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(vertical ? 12 : 22),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: vertical ? 6 : 14,
            vertical: 6,
          ),
          child: SizedBox(
            width: vertical ? double.infinity : null,
            child: vertical
                ? _FourCharacterLabel(
                    label: label,
                    color: selected ? selectedText : unselectedText,
                  )
                : Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? selectedText : unselectedText,
                      fontSize: 13,
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
                    border: Border.all(color: unselectedBackground, width: 1.5),
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
