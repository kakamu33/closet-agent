import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers.dart';
import '../../../core/media/image_draft.dart';
import '../../../core/media/photo_picker.dart';
import '../../../core/widgets/cutout_wand_button.dart';
import '../../../core/widgets/item_image.dart';
import '../data/background_removal_service.dart';
import '../domain/wardrobe_item.dart';
import '../domain/wardrobe_tag.dart';

class ItemFormScreen extends ConsumerStatefulWidget {
  const ItemFormScreen({super.key, this.item});
  final WardrobeItem? item;

  @override
  ConsumerState<ItemFormScreen> createState() => _ItemFormScreenState();
}

class _ItemFormScreenState extends ConsumerState<ItemFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.item?.name);
  late final _brand = TextEditingController(text: widget.item?.brand);
  late final _color = TextEditingController(text: widget.item?.color);
  late final _price = TextEditingController(
    text: widget.item?.price?.toString() ?? '',
  );
  late final _notes = TextEditingController(text: widget.item?.notes);
  late String _currency = widget.item?.currency ?? 'CNY';
  late final List<String> _photos = [...?widget.item?.imagePaths];
  late final Set<String> _tagIds = {...?widget.item?.tagIds};
  late final String _itemId = widget.item?.id ?? const Uuid().v4();
  var _saving = false;
  var _showNameError = false;
  final Set<String> _removingBackground = {};

  late final ImageDraft _imageDraft;

  @override
  void initState() {
    super.initState();
    _imageDraft = ImageDraft(delete: ref.read(imageStoreProvider).delete);
  }

  @override
  void dispose() {
    _imageDraft.close();
    _name.dispose();
    _brand.dispose();
    _color.dispose();
    _price.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _addPhotos() async {
    final picked = await pickPhotos(context);
    if (picked.isEmpty || !mounted) return;
    final store = ref.read(imageStoreProvider);
    try {
      for (final image in picked) {
        final path = await store.persist(image);
        _imageDraft.track(path);
        if (mounted) setState(() => _photos.add(path));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('照片保存失败，请重试。')));
      }
    }
  }

  Future<void> _confirmRemoveBackground(String photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除图片背景？'),
        content: const Text('图片将上传至 Poof 处理，完成后会用透明背景版本替换原图。'),
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
    if (confirmed == true && mounted) await _removeBackground(photo);
  }

  Future<void> _removeBackground(String photo) async {
    setState(() => _removingBackground.add(photo));
    try {
      final transparentImage = await ref
          .read(backgroundRemovalServiceProvider)
          .removeBackground(imagePath: photo);
      _imageDraft.track(transparentImage);
      if (!mounted) return;
      setState(() {
        final index = _photos.indexOf(photo);
        if (index >= 0) _photos[index] = transparentImage;
      });
      _showMessage('已移除背景，透明 PNG 将随单品一起保存。');
    } on BackgroundRemovalException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('抠图失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _removingBackground.remove(photo));
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _toggleTag(String id, List<WardrobeTag> allTags) {
    if (_tagIds.contains(id)) {
      _tagIds.remove(id);
    } else {
      // 检查数量限制
      final tag = allTags.firstWhere((t) => t.id == id);
      if (tag.isPrimary) {
        final primaryCount = allTags
            .where((t) => t.isPrimary && _tagIds.contains(t.id))
            .length;
        if (primaryCount >= WardrobeTag.maxPrimaryTagCount) {
          _showMessage('一级标签最多 ${WardrobeTag.maxPrimaryTagCount} 个');
          return;
        }
      } else {
        final secondaryCount = allTags
            .where((t) => !t.isPrimary && _tagIds.contains(t.id))
            .length;
        if (secondaryCount >= WardrobeTag.maxSecondaryTagCount) {
          _showMessage('二级标签最多 ${WardrobeTag.maxSecondaryTagCount} 个');
          return;
        }
      }
      _tagIds.add(id);
    }
    setState(() {});
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (_name.text.trim().isEmpty) {
      setState(() => _showNameError = true);
      _showMessage('名称为必填项，请填写后再保存。');
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final item = WardrobeItem(
        syncVersion: widget.item?.syncVersion ?? 0,
        id: _itemId,
        name: _name.text.trim(),
        tagIds: _tagIds.toList(),
        imagePaths: List.of(_photos),
        brand: _brand.text.trim(),
        color: _color.text.trim(),
        notes: _notes.text.trim(),
        currency: _currency,
        price: double.tryParse(_price.text.trim()),
        createdAt: widget.item?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );
      _imageDraft.preserve(item.imagePaths);
      await ref.read(wardrobeItemsProvider.notifier).save(item);
      _imageDraft.commit(item.imagePaths);
      if (mounted) Navigator.pop(context, item);
    } catch (_) {
      if (mounted) _showMessage('保存失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tags = ref.watch(wardrobeTagsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(widget.item == null ? '录入单品' : '编辑单品')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('单品照片', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            SizedBox(
              height: 126,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  ..._photos.map(
                    (photo) => Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: SizedBox(
                        width: 112,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: ItemImage(
                                path: photo,
                                size: 112,
                                radius: 16,
                              ),
                            ),
                            if (_removingBackground.contains(photo))
                              const Positioned.fill(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Color(0x66000000),
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(16),
                                    ),
                                  ),
                                  child: Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            else
                              Positioned(
                                left: 7,
                                bottom: 7,
                                child: CutoutWandButton(
                                  onTap: () => _confirmRemoveBackground(photo),
                                ),
                              ),
                            Positioned(
                              top: 2,
                              right: 2,
                              child: IconButton(
                                tooltip: '删除照片',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(
                                  width: 28,
                                  height: 28,
                                ),
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.close, size: 19),
                                onPressed: () =>
                                    setState(() => _photos.remove(photo)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 116,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                      ),
                      onPressed: _addPhotos,
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('添加照片'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _name,
              autovalidateMode: _showNameError
                  ? AutovalidateMode.always
                  : AutovalidateMode.onUserInteraction,
              onChanged: (value) {
                if (_showNameError && value.trim().isNotEmpty) {
                  setState(() => _showNameError = false);
                }
              },
              decoration: const InputDecoration(
                labelText: '名称 *',
                hintText: '例如：叠序',
              ),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请输入名称' : null,
            ),
            const SizedBox(height: 18),
            Text('标签', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            tags.when(
              data: (allTags) => _AccordionTagSelector(
                tags: allTags,
                selectedIds: _tagIds,
                onToggle: (id) => _toggleTag(id, allTags),
              ),
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => const Text('标签加载失败'),
            ),
            const SizedBox(height: 22),
            Text('品牌（可选）', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextFormField(
              controller: _brand,
              decoration: const InputDecoration(hintText: '例如：叠序'),
            ),
            const SizedBox(height: 18),
            Text('颜色（可选）', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextFormField(
              controller: _color,
              decoration: const InputDecoration(hintText: '例如：米白色'),
            ),
            const SizedBox(height: 18),
            Text('价格（可选）', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 132,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _currency,
                    decoration: const InputDecoration(hintText: '币种'),
                    items: const [
                      DropdownMenuItem(value: 'CNY', child: Text('CNY ¥')),
                      DropdownMenuItem(value: 'USD', child: Text('USD \$')),
                      DropdownMenuItem(value: 'EUR', child: Text('EUR €')),
                      DropdownMenuItem(value: 'JPY', child: Text('JPY ¥')),
                    ],
                    onChanged: (value) => setState(() => _currency = value!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(hintText: '输入金额'),
                    validator: (value) =>
                        value == null ||
                            value.trim().isEmpty ||
                            double.tryParse(value.trim()) != null
                        ? null
                        : '请输入有效金额',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text('衣物说明（可选）', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextFormField(
              controller: _notes,
              maxLines: 4,
              decoration: const InputDecoration(hintText: '记录它的特点、回忆或小故事'),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  _saving
                      ? '保存中…'
                      : widget.item == null
                      ? '保存单品'
                      : '保存修改',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 方案 A：手风琴式标签选择器。
///
/// 一级标签各占一行，点击可展开/折叠其下属的二级标签；
/// 二级标签使用 FilterChip 行内排列。每个标签都可以被选中/取消选中，
/// 遵守一级/二级标签的数量上限。
class _AccordionTagSelector extends StatefulWidget {
  const _AccordionTagSelector({
    required this.tags,
    required this.selectedIds,
    required this.onToggle,
  });

  final List<WardrobeTag> tags;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggle;

  @override
  State<_AccordionTagSelector> createState() => _AccordionTagSelectorState();
}

class _AccordionTagSelectorState extends State<_AccordionTagSelector> {
  /// 哪些一级标签是展开的
  final Set<String> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final primary = widget.tags.where((t) => t.isPrimary).toList();
    if (primary.isEmpty) {
      return const Text('暂无标签，请先在衣橱页添加标签。');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 数量配额提示
        _buildQuotaHint(),
        const SizedBox(height: 8),
        ...primary.map((p) => _buildPrimarySection(p)),
      ],
    );
  }

  Widget _buildQuotaHint() {
    final primarySelected = widget.tags
        .where((t) => t.isPrimary && widget.selectedIds.contains(t.id))
        .length;
    final secondarySelected = widget.tags
        .where((t) => !t.isPrimary && widget.selectedIds.contains(t.id))
        .length;
    return Text(
      '一级 $primarySelected/${WardrobeTag.maxPrimaryTagCount}  '
      '二级 $secondarySelected/${WardrobeTag.maxSecondaryTagCount}',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildPrimarySection(WardrobeTag primary) {
    final children = widget.tags
        .where((t) => t.parentId == primary.id)
        .toList();
    final isExpanded = _expanded.contains(primary.id);
    final isSelected = widget.selectedIds.contains(primary.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => widget.onToggle(primary.id),
          borderRadius: BorderRadius.circular(8),
          child: Row(
            children: [
              Checkbox(
                value: isSelected,
                onChanged: (_) => widget.onToggle(primary.id),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Text(
                  primary.name,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (children.isNotEmpty)
                IconButton(
                  icon: Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                  ),
                  onPressed: () => setState(
                    () => _expanded.contains(primary.id)
                        ? _expanded.remove(primary.id)
                        : _expanded.add(primary.id),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
        if (isExpanded && children.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: children.map((child) {
                final selected = widget.selectedIds.contains(child.id);
                return FilterChip(
                  label: Text(child.name),
                  selected: selected,
                  onSelected: (_) => widget.onToggle(child.id),
                );
              }).toList(),
            ),
          ),
        const SizedBox(height: 4),
      ],
    );
  }
}
