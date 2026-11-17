import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/media/photo_picker.dart';
import '../../../core/widgets/item_image.dart';
import '../../../core/widgets/sync_status_tile.dart';
import '../../auth/domain/auth_user.dart';
import '../domain/user_profile.dart';

final _legacyImportAvailableProvider = FutureProvider<bool>((ref) async {
  if (ref.watch(authSessionProvider).value == null) return false;
  return ref.watch(databaseProvider).hasLegacyDataForImport();
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemCount = ref.watch(wardrobeItemsProvider).value?.length;
    final outfitCount = ref.watch(outfitsProvider).value?.length;
    final profile = ref.watch(userProfileProvider);
    final account = ref.watch(authSessionProvider).asData?.value;
    final canImport = ref.watch(_legacyImportAvailableProvider).value == true;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        backgroundColor: const Color(0xFFF7F5F1),
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: const Text(
          '个人',
          style: TextStyle(
            fontFamily: 'LXGWWenKai',
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: Color(0xFF5C3A20),
          ),
        ),
      ),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('个人资料加载失败：$error')),
        data: (value) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            _ProfileHeader(
              profile: value,
              itemCount: itemCount,
              outfitCount: outfitCount,
              username: account?.username,
              onEdit: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _ProfileEditScreen(profile: value),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Divider(height: 1, color: Color(0xFFE5E0D9)),
            const SyncStatusTile(),
            const Divider(height: 1, color: Color(0xFFE5E0D9)),
            const SizedBox(height: 20),
            _SettingsGroup(
              children: [
                if (canImport)
                  _SettingsRow(
                    title: '导入旧设备数据',
                    onTap: () => _importLegacy(context, ref),
                  ),
                _SettingsRow(
                  title: '账号与安全',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const _SettingsDetailScreen(),
                    ),
                  ),
                ),
                _SettingsRow(
                  title: '隐私与数据',
                  onTap: () => _openInfo(context, '隐私与数据', const [
                    ('衣物与搭配', '单品、搭配和分类会同步到当前账号。未完成同步的修改保留在本机，可在个人页查看状态并重试。'),
                    (
                      '照片与抠图',
                      '图片云存储可用时，头像、单品和搭配照片会随数据上传；未能上传时保留在本机。使用抠图功能需要将照片上传至抠图服务处理。',
                    ),
                    ('个人资料', '昵称、签名和头像会同步到当前账号。离线修改保留在本机，多端冲突需要你确认保留哪一份。'),
                    ('仅在此设备保存', '线上衣柜布局、未录入草稿和自定义颜色候选保存在当前设备。'),
                    (
                      '删除账号',
                      '可在“账号与安全”中注销账号。注销会永久删除账号及关联数据，无法恢复；请先确认没有需要保留的内容。',
                    ),
                  ]),
                ),
                _SettingsRow(
                  title: '使用帮助',
                  onTap: () => _openInfo(context, '使用帮助', const [
                    ('整理衣橱', '在衣橱页添加衣物，填写名称并选择分类。长按分类可进入编辑和拖动排序模式。'),
                    ('保存搭配', '在搭配页创建搭配，组合已有单品，也可以手动填写其他单品。AI 帮我搭配尚未开放。'),
                    ('线上衣柜', '把衣物放在可以拖动、分区的白板上，按自己的收纳习惯整理。布局仅保存在当前设备。'),
                    ('同步遇到问题', '保留当前设备的数据，联网后点击同步按钮重试。照片未上传时，请勿清除浏览器数据或卸载应用。'),
                  ]),
                ),
                _SettingsRow(
                  title: '关于叠序',
                  onTap: () => _openInfo(context, '关于叠序', const [
                    ('叠序', '整理已有衣物，记录喜欢的搭配。'),
                    ('当前版本', '1.0.0'),
                  ]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsDetailScreen extends ConsumerWidget {
  const _SettingsDetailScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(authSessionProvider).asData?.value;
    return Scaffold(
      appBar: AppBar(title: const Text('账号与安全')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          if (account != null) ...[
            _AccountCard(account: account),
            const SizedBox(height: 20),
            _LogoutCard(),
            const SizedBox(height: 20),
            const _DeleteAccountCard(),
          ] else
            const Card(
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('未登录'),
                subtitle: Text('登录后可管理账号与云同步'),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profile,
    required this.username,
    required this.itemCount,
    required this.outfitCount,
    required this.onEdit,
  });
  final UserProfile profile;
  final String? username;
  final int? itemCount;
  final int? outfitCount;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _ProfileAvatar(path: profile.avatarPath, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.nickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    username == null ? '本机个人资料' : '@$username',
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
            TextButton(
              onPressed: onEdit,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF71675E),
                textStyle: const TextStyle(fontSize: 12),
              ),
              child: const Text('编辑资料 ›'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          '${itemCount ?? '—'} 件单品 · ${outfitCount ?? '—'} 套搭配',
          style: const TextStyle(fontSize: 13, color: Color(0xFF71675E)),
        ),
      ],
    ),
  );
}

void _openInfo(
  BuildContext context,
  String title,
  List<(String, String)> sections,
) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            for (final section in sections)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.$1,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      section.$2,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.7,
                        color: Color(0xFF71675E),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const Divider(height: 1, color: Color(0xFFEAE5DE)),
          children[i],
        ],
      ],
    ),
  );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.title, required this.onTap});
  final String title;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(
      title,
      style: const TextStyle(fontSize: 14, color: Color(0xFF2D2C29)),
    ),
    trailing: const Icon(
      Icons.chevron_right_rounded,
      size: 18,
      color: Color(0xFFABA298),
    ),
    onTap: onTap,
  );
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.account});

  final AuthUser account;

  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      children: [
        ListTile(
          leading: const Icon(Icons.verified_user_outlined),
          title: Text(
            account.username,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            '${account.email}\n${account.emailVerified ? '邮箱已验证' : '邮箱未验证'}',
            style: const TextStyle(fontSize: 12, height: 1.6),
          ),
        ),
      ],
    ),
  );
}

class _LogoutCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
    child: ListTile(
      leading: const Icon(Icons.logout_outlined),
      title: const Text('退出登录'),
      subtitle: const Text('下次使用需要重新登录'),
      onTap: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('确认退出登录？'),
            content: const Text('退出后需要使用用户名或邮箱和密码再次登录。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('退出登录'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        await ref.read(authSessionProvider.notifier).logout();
        // 退出登录后 [DiexuApp] 会把根页面切回登录页，但当前设置详情页是
        // 通过 Navigator.push 叠加在根页面之上的，不会被自动移除；这里
        // 主动清空导航栈，回到（已切换为登录页的）根路由。
        if (context.mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      },
    ),
  );
}

class _DeleteAccountCard extends ConsumerWidget {
  const _DeleteAccountCard();

  static const _confirmWord = '删除';

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
    color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.35),
    child: ListTile(
      leading: Icon(
        Icons.delete_forever_outlined,
        color: Theme.of(context).colorScheme.error,
      ),
      title: Text(
        '注销账号',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
      subtitle: const Text('永久删除账号及全部衣橱数据，无法恢复'),
      onTap: () => _confirmAndDelete(context, ref),
    ),
  );

  Future<void> _confirmAndDelete(BuildContext context, WidgetRef ref) async {
    final firstConfirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认注销账号？'),
        content: const Text(
          '注销后，账号、所有单品、标签、搭配及个人资料都会被永久删除，'
          '且无法找回，此后无法再用原账号密码登录。请谨慎操作。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    if (firstConfirm != true || !context.mounted) return;

    final controller = TextEditingController();
    // 三种结果：null/false = 用户主动取消；true = 已点击提交按钮（是否放行
    // 还需在下面再校验一次输入内容，防止极端情况下按钮态与文本不同步）。
    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('最后确认'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('请输入“$_confirmWord”以确认永久注销账号：'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: _confirmWord),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('永久注销'),
          ),
        ],
      ),
    );
    final matched = controller.text.trim() == _confirmWord;
    controller.dispose();
    if (submitted != true) return;
    if (!matched) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('输入内容不匹配，已取消注销')));
      }
      return;
    }

    try {
      await ref.read(authSessionProvider.notifier).deleteAccount();
      // 注销成功后 [DiexuApp] 会把根页面切回登录页，但当前设置详情页是
      // 通过 Navigator.push 叠加在根页面之上的，不会被自动移除；这里
      // 主动清空导航栈，回到（已切换为登录页的）根路由。
      if (context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('注销失败：$error')));
      }
    }
  }
}

class _ProfileEditScreen extends ConsumerStatefulWidget {
  const _ProfileEditScreen({required this.profile});
  final UserProfile profile;

  @override
  ConsumerState<_ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<_ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _nickname = TextEditingController(text: widget.profile.nickname);
  late final _signature = TextEditingController(text: widget.profile.signature);
  late String? _avatarPath = widget.profile.avatarPath;
  var _saving = false;
  var _allowPop = false;
  var _confirming = false;
  bool get _dirty =>
      _nickname.text != widget.profile.nickname ||
      _signature.text != widget.profile.signature ||
      _avatarPath != widget.profile.avatarPath;

  @override
  void initState() {
    super.initState();
    _nickname.addListener(_changed);
    _signature.addListener(_changed);
  }

  void _changed() => setState(() {});
  @override
  void dispose() {
    _nickname.dispose();
    _signature.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context);
  }

  Future<void> _requestLeave() async {
    if (_saving || _confirming) return;
    if (!_dirty) {
      await _close();
      return;
    }
    _confirming = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃本次修改？'),
        content: const Text('修改尚未保存。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('放弃修改'),
          ),
        ],
      ),
    );
    _confirming = false;
    if (discard == true && mounted) await _close();
  }

  Future<void> _pickAvatar() async {
    try {
      final images = await pickPhotos(
        context,
        multiple: false,
        imageQuality: 80,
        maxWidth: 512,
      );
      if (images.isEmpty || !mounted) return;
      final path = await ref.read(imageStoreProvider).persist(images.single);
      if (mounted) setState(() => _avatarPath = path);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('头像读取失败，请重试')));
      }
    }
  }

  Future<void> _save() async {
    if (_saving || !_dirty || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      await ref
          .read(userProfileProvider.notifier)
          .save(
            UserProfile(
              id: widget.profile.id,
              syncVersion: widget.profile.syncVersion,
              nickname: _nickname.text.trim(),
              signature: _signature.text.trim(),
              avatarPath: _avatarPath,
            ),
          );
      if (mounted) await _close();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('资料保存失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop || (!_dirty && !_saving),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _requestLeave();
    },
    child: Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F5F1),
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        leading: BackButton(onPressed: _saving ? null : _requestLeave),
        title: const Text(
          '编辑资料',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _dirty && !_saving ? _save : null,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF805A3B),
              ),
              child: Text(_saving ? '保存中…' : '保存'),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _saving ? null : _pickAvatar,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      _ProfileAvatar(path: _avatarPath, size: 48),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Text(
                          '更换头像',
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF71675E),
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.photo_camera_outlined,
                        size: 18,
                        color: Color(0xFFABA298),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            _ProfileField(
              label: '昵称',
              controller: _nickname,
              maxLength: 20,
              enabled: !_saving,
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请输入昵称' : null,
            ),
            const SizedBox(height: 24),
            _ProfileField(
              label: '个性签名',
              controller: _signature,
              maxLength: 60,
              lines: 2,
              enabled: !_saving,
            ),
            const SizedBox(height: 24),
            const Text(
              '昵称、签名和头像同步到当前账号；未同步的修改保留在本机',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: Color(0xFF918A82),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ProfileField extends StatelessWidget {
  const _ProfileField({
    required this.label,
    required this.controller,
    required this.maxLength,
    required this.enabled,
    this.lines = 1,
    this.validator,
  });
  final String label;
  final TextEditingController controller;
  final int maxLength;
  final int lines;
  final bool enabled;
  final String? Function(String?)? validator;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 12, color: Color(0xFF807B74)),
      ),
      const SizedBox(height: 4),
      TextFormField(
        controller: controller,
        enabled: enabled,
        maxLength: maxLength,
        minLines: lines,
        maxLines: lines,
        validator: validator,
        style: const TextStyle(
          fontSize: 15,
          height: 1.6,
          color: Color(0xFF2D2C29),
        ),
        textInputAction: lines == 1
            ? TextInputAction.next
            : TextInputAction.newline,
        decoration: InputDecoration(
          filled: false,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: const UnderlineInputBorder(
            borderSide: BorderSide(color: Color(0xFFE5E0D9)),
          ),
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Color(0xFFE5E0D9)),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF9A8672)),
          ),
          disabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Color(0xFFE5E0D9)),
          ),
          counterStyle: const TextStyle(fontSize: 11, color: Color(0xFF918A82)),
        ),
      ),
    ],
  );
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.path, required this.size});
  final String? path;
  final double size;

  @override
  Widget build(BuildContext context) => ClipOval(
    child: SizedBox(
      width: size,
      height: size,
      child: path == null
          ? const ColoredBox(
              color: Color(0xFFEAD7C8),
              child: Icon(
                Icons.person_rounded,
                size: 38,
                color: Color(0xFF795548),
              ),
            )
          : ItemImage(path: path, size: size, radius: size / 2),
    ),
  );
}

Future<void> _importLegacy(BuildContext context, WidgetRef ref) async {
  final database = ref.read(databaseProvider);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('导入到当前账号？'),
      content: const Text(
        '旧版本数据没有可靠的账号归属。请仅在确认这些衣物和搭配属于你时导入；原始旧数据会保留。已有云端同名或同 ID 内容不会被直接覆盖。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('确认是我的数据，导入'),
        ),
      ],
    ),
  );
  if (confirmed != true ||
      !context.mounted ||
      !identical(database, ref.read(databaseProvider))) {
    return;
  }
  try {
    await database.importLegacyData(confirmed: true);
    if (!context.mounted) return;
    ref.invalidate(_legacyImportAvailableProvider);
    ref.invalidate(wardrobeItemsProvider);
    ref.invalidate(outfitsProvider);
    ref.invalidate(wardrobeTagsProvider);
    ref.invalidate(outfitTagsProvider);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('旧数据已导入，待同步内容会保留到云端确认')));
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('导入未完成，原始数据仍保留，可稍后重试')));
    }
  }
}
