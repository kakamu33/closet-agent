import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers.dart';
import '../../../core/widgets/item_image.dart';
import '../../wardrobe/domain/wardrobe_item.dart';
import '../../wardrobe/presentation/item_detail_screen.dart';
import '../domain/outfit.dart';

class OutfitFormScreen extends ConsumerStatefulWidget {
  const OutfitFormScreen({super.key, this.outfit});
  final Outfit? outfit;

  @override
  ConsumerState<OutfitFormScreen> createState() => _OutfitFormScreenState();
}

class _OutfitFormScreenState extends ConsumerState<OutfitFormScreen> {
  final _key = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _notes = TextEditingController();
  final Set<String> _tagIds = {};
  final List<OutfitEntry> _entries = [];
  final List<String> _coverPaths = [];
  var _saving = false;

  @override
  void initState() {
    super.initState();
    final outfit = widget.outfit;
    _name.text = outfit?.name ?? '';
    _tagIds.addAll(outfit?.tags ?? const <String>[]);
    _notes.text = outfit?.notes ?? '';
    _entries.addAll(outfit?.entries ?? []);
    _coverPaths.addAll(outfit?.photos ?? const []);
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    final images = await ImagePicker().pickMultiImage(imageQuality: 75, maxWidth: 1280);
    if (images.isEmpty) return;
    final paths = await Future.wait(images.map(ref.read(imageStoreProvider).persist));
    if (mounted) setState(() => _coverPaths.addAll(paths));
  }

  Future<void> _addEntry(List<WardrobeItem> items) async {
    final entry = await showModalBottomSheet<OutfitEntry>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _EntryPicker(items: items),
    );
    if (entry != null) setState(() => _entries.add(entry));
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    if (_entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请至少添加一件单品')));
      return;
    }
    setState(() => _saving = true);
    try {
      final outfit = Outfit(
        id: widget.outfit?.id ?? const Uuid().v4(),
        name: _name.text.trim(),
        // 保留旧字段以兼容已存在的数据；新的搭配仅使用标签分类。
        occasion: '',
        season: '',
        tags: _tagIds.toList(),
        entries: _entries,
        coverPath: _coverPaths.isEmpty ? null : _coverPaths.first,
        coverPaths: _coverPaths,
        notes: _notes.text.trim(),
        createdAt: widget.outfit?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await ref.read(outfitsProvider.notifier).save(outfit);
      if (mounted) Navigator.pop(context, outfit);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(wardrobeItemsProvider).value ?? [];
    return Scaffold(
      appBar: AppBar(title: Text(widget.outfit == null ? '创建搭配' : '编辑搭配')),
      body: Form(
        key: _key,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('搭配照片', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            SizedBox(height: 170, child: ListView(scrollDirection: Axis.horizontal, children: [
              ..._coverPaths.asMap().entries.map((entry) => Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Stack(children: [
                  ItemImage(path: entry.value, size: 170, radius: 20),
                  Positioned(top: 6, right: 6, child: IconButton.filledTonal(icon: const Icon(Icons.close), onPressed: () => setState(() => _coverPaths.removeAt(entry.key)))),
                ]),
              )),
              OutlinedButton.icon(onPressed: _pickCover, icon: const Icon(Icons.add_photo_alternate_outlined), label: const Text('添加搭配照片')),
            ])),
            const SizedBox(height: 20),
            TextFormField(controller: _name, decoration: const InputDecoration(labelText: '搭配名称 *'), validator: (value) => value == null || value.trim().isEmpty ? '请输入名称' : null),
            const SizedBox(height: 18),
            Text('搭配标签', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            ref.watch(outfitTagsProvider).when(
              data: (tags) => Wrap(spacing: 8, runSpacing: 8, children: tags.map((tag) => FilterChip(label: Text(tag.isPrimary ? tag.name : '  ${tag.name}'), selected: _tagIds.contains(tag.id), onSelected: (selected) => setState(() { if (selected) { _tagIds.add(tag.id); } else { _tagIds.remove(tag.id); } }))).toList()),
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => const Text('标签加载失败'),
            ),
            const SizedBox(height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('搭配单品', style: Theme.of(context).textTheme.titleLarge),
              TextButton.icon(onPressed: () => _addEntry(items), icon: const Icon(Icons.add), label: const Text('添加')),
            ]),
            if (_entries.isEmpty) Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)), child: const Text('可添加衣橱中的单品，也可添加暂未录入的临时单品。')),
            ..._entries.asMap().entries.map((pair) {
              final entry = pair.value;
              final item = entry.itemId == null
                  ? null
                  : items.where((candidate) => candidate.id == entry.itemId).firstOrNull;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: ListTile(
                  hoverColor: Colors.transparent,
                  splashColor: Colors.transparent,
                  contentPadding: const EdgeInsets.fromLTRB(10, 7, 6, 7),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 46,
                      height: 46,
                      child: entry.imagePath == null
                          ? ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest, child: Icon(entry.isLinked ? Icons.checkroom : Icons.link_off_outlined, size: 21))
                          : ItemImage(path: entry.imagePath, width: 46, height: 46, radius: 0),
                    ),
                  ),
                  title: Text(entry.name),
                  subtitle: Text(entry.isLinked ? '衣橱单品 · 点击查看详情' : '临时单品'),
                  onTap: item == null ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => ItemDetailScreen(item: item))),
                  trailing: IconButton(tooltip: '移除单品', icon: const Icon(Icons.close), onPressed: () => setState(() => _entries.removeAt(pair.key))),
                ),
              );
            }),
            const SizedBox(height: 14),
            TextFormField(controller: _notes, maxLines: 3, decoration: const InputDecoration(labelText: '搭配灵感（可选）')),
            const SizedBox(height: 28),
            FilledButton(onPressed: _saving ? null : _save, child: Padding(padding: const EdgeInsets.all(14), child: Text(_saving ? '保存中…' : widget.outfit == null ? '保存搭配' : '保存修改'))),
          ],
        ),
      ),
    );
  }
}

class _EntryPicker extends StatefulWidget {
  const _EntryPicker({required this.items});
  final List<WardrobeItem> items;

  @override
  State<_EntryPicker> createState() => _EntryPickerState();
}

class _EntryPickerState extends State<_EntryPicker> {
  final _custom = TextEditingController();

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: SizedBox(
        height: 470,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('添加单品', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: TextField(controller: _custom, decoration: const InputDecoration(hintText: '输入未录入单品名称'))),
            const SizedBox(width: 8),
            IconButton.filled(onPressed: () { if (_custom.text.trim().isNotEmpty) Navigator.pop(context, OutfitEntry(name: _custom.text.trim())); }, icon: const Icon(Icons.add)),
          ]),
          const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Text('或从衣橱选择')),
          Expanded(child: widget.items.isEmpty ? const Center(child: Text('衣橱暂无单品')) : ListView.builder(
            itemCount: widget.items.length,
            itemBuilder: (_, index) {
              final item = widget.items[index];
              return ListTile(
                leading: ClipRRect(borderRadius: BorderRadius.circular(8), child: ItemImage(path: item.imagePath, width: 44, height: 44, radius: 0)),
                title: Text(item.name),
                onTap: () => Navigator.pop(context, OutfitEntry(itemId: item.id, name: item.name, imagePath: item.imagePath)),
              );
            },
          )),
        ]),
      ),
    ),
  );
}

