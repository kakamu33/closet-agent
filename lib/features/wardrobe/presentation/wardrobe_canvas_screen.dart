import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/widgets/text_entry_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers.dart';
import '../../../core/widgets/item_image.dart';
import '../domain/wardrobe_canvas_layout.dart';
import '../domain/wardrobe_canvas_region.dart';
import '../domain/wardrobe_item.dart';
import 'item_detail_screen.dart';

const _canvasExtent = 100000.0;
const _canvasOrigin = Offset(_canvasExtent / 2, _canvasExtent / 2);
const _defaultCardSize = Size(138, 174);
const _editorToolbarWidth = 148.0;
const _editorCardTop = 44.0;

double _editorCardLeft(double cardWidth) =>
    ((_editorToolbarWidth - cardWidth) / 2).clamp(16.0, double.infinity);

class WardrobeCanvasScreen extends ConsumerStatefulWidget {
  const WardrobeCanvasScreen({super.key});

  @override
  ConsumerState<WardrobeCanvasScreen> createState() =>
      _WardrobeCanvasScreenState();
}

class _WardrobeCanvasScreenState extends ConsumerState<WardrobeCanvasScreen> {
  final _transformController = TransformationController();
  final _positions = <String, Offset>{};
  final _sizes = <String, Size>{};
  final _images = <String, String?>{};
  final _zIndexes = <String, int>{};
  final _regionPositions = <String, Offset>{};
  Set<String> _movingItemIds = {};
  Timer? _debounce;
  Size? _viewport;
  String? _editingItemId;
  int _activeResizeHandles = 0;
  bool _drawingRegion = false;
  Offset? _regionStart;
  Offset? _regionEnd;
  int _regionColor = 0xFF6750A4;
  CanvasRegionShape _regionShape = CanvasRegionShape.rounded;
  bool _hasCenteredInitialViewport = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _transformController.dispose();
    super.dispose();
  }

  Offset _initialPosition(int index) =>
      _canvasOrigin + Offset((index % 8) * 190, (index ~/ 8) * 220);

  void _center() {
    if (!mounted) return;
    final viewport = _viewport;
    if (viewport == null) return;
    _transformController.value = Matrix4.translationValues(
      viewport.width / 2 - _canvasOrigin.dx,
      viewport.height / 2 - _canvasOrigin.dy,
      0,
    );
  }

  void _saveLayout(String id) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      final position = _positions[id];
      if (position == null) return;
      ref
          .read(wardrobeCanvasLayoutsProvider.notifier)
          .save(
            WardrobeCanvasLayout(
              itemId: id,
              x: position.dx,
              y: position.dy,
              width: _sizes[id]?.width ?? _defaultCardSize.width,
              height: _sizes[id]?.height ?? _defaultCardSize.height,
              zIndex: _zIndexes[id] ?? 0,
              displayImagePath: _images[id],
              updatedAt: DateTime.now(),
            ),
          );
    });
  }

  void _moveItem(String id, Offset delta) =>
      setState(() => _positions[id] = (_positions[id] ?? Offset.zero) + delta);

  void _resizeItem(String id, Offset delta, {required bool keepAspectRatio}) {
    final size = _sizes[id] ?? _defaultCardSize;
    final aspectRatio = size.width / size.height;
    final next = keepAspectRatio
        ? (() {
            final scaleDelta = delta.dx.abs() >= delta.dy.abs()
                ? delta.dx
                : delta.dy * aspectRatio;
            final width = (size.width + scaleDelta)
                .clamp(80.0, 500.0)
                .toDouble();
            return Size(
              width,
              (width / aspectRatio).clamp(100.0, 650.0).toDouble(),
            );
          })()
        : Size(
            (size.width + delta.dx).clamp(80.0, 500.0).toDouble(),
            (size.height + delta.dy).clamp(100.0, 650.0).toDouble(),
          );
    setState(() => _sizes[id] = next);
  }

  void _restoreItemSize(String id) {
    setState(() => _sizes[id] = _defaultCardSize);
    _saveLayout(id);
  }

  Future<void> _renameItem(WardrobeItem item) async {
    final name = await showTextEntryDialog(
      context,
      title: '修改衣物名称',
      initial: item.name,
    );
    if (!mounted || name == null || name.isEmpty) return;
    await ref
        .read(wardrobeItemsProvider.notifier)
        .save(item.copyWith(name: name, updatedAt: DateTime.now()));
  }

  void _cycleImage(WardrobeItem item, int direction) {
    if (item.imagePaths.isEmpty) return;
    if (item.imagePaths.length == 1) {
      _notice('该衣物仅有一张图片');
      return;
    }
    final current = _images[item.id] ?? item.imagePaths.first;
    final index = item.imagePaths.indexOf(current);
    final target = index + direction;
    if (target < 0) return _notice('你已经滑到了衣物的第一张图片');
    if (target >= item.imagePaths.length) return _notice('你已经滑到了衣物的最后一张图片');
    setState(() => _images[item.id] = item.imagePaths[target]);
    _saveLayout(item.id);
  }

  void _notice(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  void _changeLayer(String id, _LayerAction action) {
    final values = _zIndexes.values;
    final current = _zIndexes[id] ?? 0;
    setState(() {
      _zIndexes[id] = switch (action) {
        _LayerAction.forward => current + 1,
        _LayerAction.backward => current - 1,
        _LayerAction.front =>
          values.isEmpty ? 0 : values.reduce((a, b) => a > b ? a : b) + 1,
        _LayerAction.back =>
          values.isEmpty ? 0 : values.reduce((a, b) => a < b ? a : b) - 1,
      };
    });
    _saveLayout(id);
  }

  Rect? get _draft => _regionStart == null || _regionEnd == null
      ? null
      : Rect.fromPoints(_regionStart!, _regionEnd!);

  Future<void> _createRegion() async {
    final rect = _draft;
    setState(() {
      _drawingRegion = false;
      _regionStart = null;
      _regionEnd = null;
    });
    if (rect == null || rect.width < 60 || rect.height < 60) return;
    final label = await showTextEntryDialog(
      context,
      title: '命名收纳区域',
      hint: '例如：吊带箱子',
    );
    if (!mounted || label == null || label.isEmpty) return;
    await ref
        .read(wardrobeCanvasRegionsProvider.notifier)
        .save(
          WardrobeCanvasRegion(
            id: const Uuid().v4(),
            label: label,
            x: rect.left,
            y: rect.top,
            width: rect.width,
            height: rect.height,
            colorValue: _regionColor,
            shape: _regionShape,
            updatedAt: DateTime.now(),
          ),
        );
  }

  Future<void> _showStylePicker() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('圈选样式', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              const Text('颜色'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                children:
                    [0xFF6750A4, 0xFFB3261E, 0xFF146C2E, 0xFF006C7A, 0xFF9A4F00]
                        .map(
                          (value) => InkWell(
                            onTap: () => update(() => _regionColor = value),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Color(value),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: value == _regionColor
                                      ? Colors.black
                                      : Colors.transparent,
                                  width: 3,
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
              ),
              const SizedBox(height: 18),
              const Text('形状'),
              const SizedBox(height: 8),
              SegmentedButton<CanvasRegionShape>(
                segments: const [
                  ButtonSegment(
                    value: CanvasRegionShape.rectangle,
                    label: Text('方形'),
                  ),
                  ButtonSegment(
                    value: CanvasRegionShape.rounded,
                    label: Text('圆角'),
                  ),
                  ButtonSegment(
                    value: CanvasRegionShape.oval,
                    label: Text('椭圆'),
                  ),
                ],
                selected: {_regionShape},
                onSelectionChanged: (value) =>
                    update(() => _regionShape = value.first),
              ),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('完成'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editRegion(WardrobeCanvasRegion region) async {
    var color = region.colorValue;
    var shape = region.shape;
    var width = region.width;
    var height = region.height;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('编辑收纳区域', style: Theme.of(context).textTheme.titleLarge),
              SegmentedButton<CanvasRegionShape>(
                segments: const [
                  ButtonSegment(
                    value: CanvasRegionShape.rectangle,
                    label: Text('方形'),
                  ),
                  ButtonSegment(
                    value: CanvasRegionShape.rounded,
                    label: Text('圆角'),
                  ),
                  ButtonSegment(
                    value: CanvasRegionShape.oval,
                    label: Text('椭圆'),
                  ),
                ],
                selected: {shape},
                onSelectionChanged: (value) =>
                    update(() => shape = value.first),
              ),
              Wrap(
                spacing: 10,
                children:
                    [0xFF6750A4, 0xFFB3261E, 0xFF146C2E, 0xFF006C7A, 0xFF9A4F00]
                        .map(
                          (v) => InkWell(
                            onTap: () => update(() => color = v),
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: Color(v),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: color == v
                                      ? Colors.black
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
              ),
              Row(
                children: [
                  const Text('宽'),
                  Expanded(
                    child: Slider(
                      value: width.clamp(80, 1000),
                      min: 80,
                      max: 1000,
                      onChanged: (v) => update(() => width = v),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  const Text('高'),
                  Expanded(
                    child: Slider(
                      value: height.clamp(60, 800),
                      min: 60,
                      max: 800,
                      onChanged: (v) => update(() => height = v),
                    ),
                  ),
                ],
              ),
              FilledButton(
                onPressed: () async {
                  final p =
                      _regionPositions[region.id] ?? Offset(region.x, region.y);
                  await ref
                      .read(wardrobeCanvasRegionsProvider.notifier)
                      .save(
                        WardrobeCanvasRegion(
                          id: region.id,
                          label: region.label,
                          x: p.dx,
                          y: p.dy,
                          width: width,
                          height: height,
                          colorValue: color,
                          shape: shape,
                          updatedAt: DateTime.now(),
                        ),
                      );
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('保存'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _inside(WardrobeCanvasRegion r, Offset point) {
    final x = point.dx - r.x, y = point.dy - r.y;
    if (x < 0 || y < 0 || x > r.width || y > r.height) return false;
    if (r.shape != CanvasRegionShape.oval) return true;
    final dx = (x - r.width / 2) / (r.width / 2),
        dy = (y - r.height / 2) / (r.height / 2);
    return dx * dx + dy * dy <= 1;
  }

  void _startRegionMove(WardrobeCanvasRegion r) => setState(
    () => _movingItemIds = _positions.entries
        .where((entry) => _inside(r, entry.value + const Offset(69, 87)))
        .map((entry) => entry.key)
        .toSet(),
  );
  void _moveRegion(WardrobeCanvasRegion r, Offset delta) => setState(() {
    _regionPositions[r.id] =
        (_regionPositions[r.id] ?? Offset(r.x, r.y)) + delta;
    for (final id in _movingItemIds) {
      _positions[id] = (_positions[id] ?? Offset.zero) + delta;
    }
  });
  Future<void> _persistRegion(WardrobeCanvasRegion r) async {
    if (!mounted) return;
    final p = _regionPositions[r.id] ?? Offset(r.x, r.y);
    await ref
        .read(wardrobeCanvasRegionsProvider.notifier)
        .save(
          WardrobeCanvasRegion(
            id: r.id,
            label: r.label,
            x: p.dx,
            y: p.dy,
            width: r.width,
            height: r.height,
            colorValue: r.colorValue,
            shape: r.shape,
            updatedAt: DateTime.now(),
          ),
        );
    for (final id in _movingItemIds) {
      _saveLayout(id);
    }
    _movingItemIds = {};
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(wardrobeItemsProvider);
    final layouts = ref.watch(wardrobeCanvasLayoutsProvider);
    final regions = ref.watch(wardrobeCanvasRegionsProvider);
    final showNames = ref.watch(wardrobeCanvasShowNamesProvider).value ?? true;
    return Scaffold(
      appBar: AppBar(
        title: const Text('线上衣柜'),
        actions: [
          IconButton(
            tooltip: _drawingRegion ? '取消圈选' : '圈选收纳区域',
            icon: Icon(_drawingRegion ? Icons.close : Icons.gesture_outlined),
            onPressed: () async {
              if (_drawingRegion) {
                setState(() => _drawingRegion = false);
              } else {
                await _showStylePicker();
                if (mounted) setState(() => _drawingRegion = true);
              }
            },
          ),
          IconButton(
            tooltip: '回到衣柜中心',
            icon: const Icon(Icons.center_focus_strong_outlined),
            onPressed: _center,
          ),
        ],
      ),
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (itemList) => layouts.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (layoutList) => regions.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (regionList) =>
                _canvas(context, itemList, layoutList, regionList, showNames),
          ),
        ),
      ),
    );
  }

  Widget _canvas(
    BuildContext context,
    List<WardrobeItem> items,
    List<WardrobeCanvasLayout> layouts,
    List<WardrobeCanvasRegion> regions,
    bool showNames,
  ) {
    if (items.isEmpty) return const Center(child: Text('先录入几件单品吧'));
    final stored = {for (final l in layouts) l.itemId: l};
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final l = stored[item.id];
      _positions.putIfAbsent(
        item.id,
        () => l == null
            ? _initialPosition(i)
            : (l.x < 25000 || l.y < 25000
                  ? _canvasOrigin + Offset(l.x, l.y)
                  : Offset(l.x, l.y)),
      );
      _sizes.putIfAbsent(
        item.id,
        () => Size(
          l?.width ?? _defaultCardSize.width,
          l?.height ?? _defaultCardSize.height,
        ),
      );
      _images.putIfAbsent(item.id, () => l?.displayImagePath);
      _zIndexes.putIfAbsent(item.id, () => l?.zIndex ?? i);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewport = constraints.biggest;
        if (!_hasCenteredInitialViewport) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _hasCenteredInitialViewport) return;
            _hasCenteredInitialViewport = true;
            if (_transformController.value == Matrix4.identity()) _center();
          });
        }
        final ordered = [...items]
          ..sort(
            (a, b) => (_zIndexes[a.id] ?? 0).compareTo(_zIndexes[b.id] ?? 0),
          );
        return ClipRect(
          child: InteractiveViewer(
            transformationController: _transformController,
            minScale: .25,
            maxScale: 3,
            boundaryMargin: const EdgeInsets.all(double.infinity),
            constrained: false,
            panEnabled: !_drawingRegion,
            child: SizedBox(
              width: _canvasExtent,
              height: _canvasExtent,
              child: CustomPaint(
                painter: _GridPainter(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () {
                          if (_editingItemId != null) {
                            setState(() => _editingItemId = null);
                          }
                        },
                      ),
                    ),
                    ...regions.map((r) {
                      final p = _regionPositions.putIfAbsent(
                        r.id,
                        () => Offset(r.x, r.y),
                      );
                      return Positioned(
                        left: p.dx,
                        top: p.dy,
                        child: _Region(
                          region: r,
                          onMoveStart: () => _startRegionMove(r),
                          onMove: (d) => _moveRegion(r, d),
                          onMoveEnd: () => _persistRegion(r),
                          onEdit: () => _editRegion(r),
                        ),
                      );
                    }),
                    ...ordered.map(
                      (item) => Positioned(
                        left:
                            _positions[item.id]!.dx -
                            (_editingItemId == item.id
                                ? _editorCardLeft(_sizes[item.id]!.width)
                                : 0),
                        top:
                            _positions[item.id]!.dy -
                            (_editingItemId == item.id ? _editorCardTop : 0),
                        child: _ItemCard(
                          item: item,
                          path: _images[item.id] ?? item.imagePath,
                          size: _sizes[item.id]!,
                          showName: showNames,
                          editing: _editingItemId == item.id,
                          onMove: (d) => _moveItem(item.id, d),
                          onMoveEnd: () => _saveLayout(item.id),
                          onOpen: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ItemDetailScreen(item: item),
                            ),
                          ),
                          onEdit: () =>
                              setState(() => _editingItemId = item.id),
                          onResizeStart: () =>
                              setState(() => _activeResizeHandles++),
                          onResize: (d) => _resizeItem(
                            item.id,
                            d,
                            keepAspectRatio: _activeResizeHandles < 2,
                          ),
                          onResizeEnd: () {
                            setState(
                              () => _activeResizeHandles =
                                  (_activeResizeHandles - 1).clamp(0, 2),
                            );
                            _saveLayout(item.id);
                          },
                          onRestoreSize: () => _restoreItemSize(item.id),
                          onImage: (d) => _cycleImage(item, d),
                          onLayer: (a) => _changeLayer(item.id, a),
                          onRename: () => _renameItem(item),
                        ),
                      ),
                    ),
                    if (_drawingRegion)
                      Positioned.fill(
                        child: GestureDetector(
                          onPanStart: (d) => setState(() {
                            _regionStart = d.localPosition;
                            _regionEnd = d.localPosition;
                          }),
                          onPanUpdate: (d) =>
                              setState(() => _regionEnd = d.localPosition),
                          onPanEnd: (_) => _createRegion(),
                          child: CustomPaint(
                            painter: _DraftPainter(
                              rect: _draft,
                              color: Color(_regionColor),
                              shape: _regionShape,
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
      },
    );
  }
}

enum _LayerAction { forward, backward, front, back }

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.item,
    required this.path,
    required this.size,
    required this.showName,
    required this.editing,
    required this.onMove,
    required this.onMoveEnd,
    required this.onOpen,
    required this.onEdit,
    required this.onResizeStart,
    required this.onResize,
    required this.onResizeEnd,
    required this.onRestoreSize,
    required this.onImage,
    required this.onLayer,
    required this.onRename,
  });
  final WardrobeItem item;
  final String? path;
  final Size size;
  final bool showName;
  final bool editing;
  final ValueChanged<Offset> onMove;
  final VoidCallback onMoveEnd;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onResizeStart;
  final ValueChanged<Offset> onResize;
  final VoidCallback onResizeEnd;
  final VoidCallback onRestoreSize;
  final ValueChanged<int> onImage;
  final ValueChanged<_LayerAction> onLayer;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final cardLeft = editing ? _editorCardLeft(size.width) : 0.0;
    final editorWidth = editing
        ? (size.width + cardLeft * 2).clamp(
            _editorToolbarWidth,
            double.infinity,
          )
        : size.width;
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onPanUpdate: editing ? null : (d) => onMove(d.delta),
      onPanEnd: editing ? null : (_) => onMoveEnd(),
      onTap: editing ? null : onOpen,
      onLongPress: onEdit,
      child: SizedBox(
        width: editorWidth,
        height: editing ? size.height + _editorCardTop : size.height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: cardLeft,
              top: editing ? _editorCardTop : 0,
              width: size.width,
              height: size.height,
              child: Material(
                elevation: 3,
                borderRadius: BorderRadius.circular(14),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Column(
                    children: [
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ItemImage(path: path, radius: 0),
                            if (editing && item.imagePaths.isNotEmpty) ...[
                              Align(
                                alignment: Alignment.centerLeft,
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.chevron_left,
                                    size: 21,
                                  ),
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  style: IconButton.styleFrom(
                                    backgroundColor: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHigh
                                        .withValues(alpha: .72),
                                    padding: const EdgeInsets.all(4),
                                    minimumSize: const Size(32, 32),
                                  ),
                                  onPressed: () => onImage(-1),
                                ),
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.chevron_right,
                                    size: 21,
                                  ),
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  style: IconButton.styleFrom(
                                    backgroundColor: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHigh
                                        .withValues(alpha: .72),
                                    padding: const EdgeInsets.all(4),
                                    minimumSize: const Size(32, 32),
                                  ),
                                  onPressed: () => onImage(1),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (showName)
                        InkWell(
                          onTap: editing ? onRename : null,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (editing) ...[
              // 卡片的实际顶部为 44；工具栏高度为 28，故 top 为 16，
              // 工具栏底边恰好贴合卡片上边且不发生重叠。
              Positioned(
                top: _editorCardTop - 28,
                left: 0,
                width: editorWidth,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: _LayerTools(
                    onLayer: onLayer,
                    onRestoreSize: onRestoreSize,
                  ),
                ),
              ),
              _ResizeHandle(
                left: cardLeft - 2,
                top: _editorCardTop - 2,
                horizontalOnStart: true,
                verticalOnStart: true,
                color: Theme.of(context).colorScheme.primary,
                onResizeStart: onResizeStart,
                onResize: onResize,
                onResizeEnd: onResizeEnd,
              ),
              _ResizeHandle(
                right: cardLeft - 2,
                top: _editorCardTop - 2,
                horizontalOnStart: false,
                verticalOnStart: true,
                color: Theme.of(context).colorScheme.primary,
                onResizeStart: onResizeStart,
                onResize: onResize,
                onResizeEnd: onResizeEnd,
              ),
              _ResizeHandle(
                // 手柄绘制的拐点位于其右下内缩 2px 处；bottom=-2
                // 让该拐点刚好落在卡片的真实下边界（44 + size.height）。
                left: cardLeft - 2,
                bottom: -2,
                horizontalOnStart: true,
                verticalOnStart: false,
                color: Theme.of(context).colorScheme.primary,
                onResizeStart: onResizeStart,
                onResize: onResize,
                onResizeEnd: onResizeEnd,
              ),
              _ResizeHandle(
                right: cardLeft - 2,
                bottom: -2,
                horizontalOnStart: false,
                verticalOnStart: false,
                color: Theme.of(context).colorScheme.primary,
                onResizeStart: onResizeStart,
                onResize: onResize,
                onResizeEnd: onResizeEnd,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({
    this.left,
    this.right,
    this.top,
    this.bottom,
    required this.horizontalOnStart,
    required this.verticalOnStart,
    required this.color,
    required this.onResizeStart,
    required this.onResize,
    required this.onResizeEnd,
  });

  final double? left;
  final double? right;
  final double? top;
  final double? bottom;
  final bool horizontalOnStart;
  final bool verticalOnStart;
  final Color color;
  final VoidCallback onResizeStart;
  final ValueChanged<Offset> onResize;
  final VoidCallback onResizeEnd;

  @override
  Widget build(BuildContext context) => Positioned(
    left: left,
    right: right,
    top: top,
    bottom: bottom,
    width: 22,
    height: 22,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => onResizeStart(),
      onPanUpdate: (details) => onResize(
        Offset(
          horizontalOnStart ? -details.delta.dx : details.delta.dx,
          verticalOnStart ? -details.delta.dy : details.delta.dy,
        ),
      ),
      onPanEnd: (_) => onResizeEnd(),
      child: CustomPaint(
        painter: _CornerHandlePainter(
          color: color,
          horizontalOnStart: horizontalOnStart,
          verticalOnStart: verticalOnStart,
        ),
      ),
    ),
  );
}

class _CornerHandlePainter extends CustomPainter {
  const _CornerHandlePainter({
    required this.color,
    required this.horizontalOnStart,
    required this.verticalOnStart,
  });

  final Color color;
  final bool horizontalOnStart;
  final bool verticalOnStart;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.square;
    // 控制点的拐角与卡片真实边界重合，线段向卡片内部延展。
    final x = horizontalOnStart ? 2.0 : size.width - 2;
    final y = verticalOnStart ? 2.0 : size.height - 2;
    final horizontalEnd = horizontalOnStart ? x + 8 : x - 8;
    final verticalEnd = verticalOnStart ? y + 8 : y - 8;
    canvas.drawLine(Offset(x, y), Offset(horizontalEnd, y), paint);
    canvas.drawLine(Offset(x, y), Offset(x, verticalEnd), paint);
  }

  @override
  bool shouldRepaint(covariant _CornerHandlePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.horizontalOnStart != horizontalOnStart ||
      oldDelegate.verticalOnStart != verticalOnStart;
}

class _LayerTools extends StatelessWidget {
  const _LayerTools({required this.onLayer, required this.onRestoreSize});
  final ValueChanged<_LayerAction> onLayer;
  final VoidCallback onRestoreSize;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(7),
      boxShadow: const [BoxShadow(blurRadius: 2, color: Colors.black26)],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LayerButton(
          tooltip: '向下一层',
          icon: Icons.keyboard_arrow_down,
          onPressed: () => onLayer(_LayerAction.backward),
        ),
        _LayerButton(
          tooltip: '置底',
          icon: Icons.vertical_align_bottom,
          onPressed: () => onLayer(_LayerAction.back),
        ),
        _LayerButton(
          tooltip: '向上一层',
          icon: Icons.keyboard_arrow_up,
          onPressed: () => onLayer(_LayerAction.forward),
        ),
        _LayerButton(
          tooltip: '置顶',
          icon: Icons.vertical_align_top,
          onPressed: () => onLayer(_LayerAction.front),
        ),
        _LayerButton(
          tooltip: '恢复原尺寸',
          icon: Icons.restart_alt_rounded,
          onPressed: onRestoreSize,
        ),
      ],
    ),
  );
}

class _LayerButton extends StatelessWidget {
  const _LayerButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    icon: Icon(icon, size: 21),
    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
    visualDensity: VisualDensity.compact,
    onPressed: onPressed,
  );
}

class _Region extends StatelessWidget {
  const _Region({
    required this.region,
    required this.onMoveStart,
    required this.onMove,
    required this.onMoveEnd,
    required this.onEdit,
  });
  final WardrobeCanvasRegion region;
  final VoidCallback onMoveStart, onMoveEnd, onEdit;
  final ValueChanged<Offset> onMove;
  @override
  Widget build(BuildContext context) {
    final color = Color(region.colorValue);
    final radius = switch (region.shape) {
      CanvasRegionShape.rectangle => BorderRadius.zero,
      CanvasRegionShape.rounded => BorderRadius.circular(12),
      CanvasRegionShape.oval => BorderRadius.circular(region.height),
    };
    return SizedBox(
      width: region.width,
      height: region.height,
      child: GestureDetector(
        onLongPress: onEdit,
        child: Stack(
          children: [
            IgnorePointer(
              child: SizedBox.expand(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .08),
                    border: Border.all(color: color, width: 2),
                    borderRadius: radius,
                  ),
                ),
              ),
            ),
            Positioned(
              left: region.shape == CanvasRegionShape.oval
                  ? region.width * .18
                  : 12,
              top: region.shape == CanvasRegionShape.oval
                  ? region.height * .16
                  : 12,
              child: GestureDetector(
                onPanStart: (_) => onMoveStart(),
                onPanUpdate: (d) => onMove(d.delta),
                onPanEnd: (_) => onMoveEnd(),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(
                      region.label,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DraftPainter extends CustomPainter {
  const _DraftPainter({
    required this.rect,
    required this.color,
    required this.shape,
  });
  final Rect? rect;
  final Color color;
  final CanvasRegionShape shape;
  @override
  void paint(Canvas c, Size s) {
    final r = rect;
    if (r == null) return;
    final f = Paint()..color = color.withValues(alpha: .1);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    switch (shape) {
      case CanvasRegionShape.rectangle:
        c.drawRect(r, f);
        c.drawRect(r, p);
      case CanvasRegionShape.rounded:
        final rr = RRect.fromRectAndRadius(r, const Radius.circular(12));
        c.drawRRect(rr, f);
        c.drawRRect(rr, p);
      case CanvasRegionShape.oval:
        c.drawOval(r, f);
        c.drawOval(r, p);
    }
  }

  @override
  bool shouldRepaint(covariant _DraftPainter o) =>
      o.rect != rect || o.color != color || o.shape != shape;
}

class _GridPainter extends CustomPainter {
  const _GridPainter({required this.color});
  final Color color;
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()..color = color.withValues(alpha: .28);
    for (var x = 0.0; x < s.width; x += 40) {
      c.drawLine(Offset(x, 0), Offset(x, s.height), p);
    }
    for (var y = 0.0; y < s.height; y += 40) {
      c.drawLine(Offset(0, y), Offset(s.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter o) => o.color != color;
}
