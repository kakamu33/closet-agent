import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/providers.dart';
import '../../../core/widgets/item_image.dart';
import '../../auth/domain/auth_user.dart';
import '../domain/user_profile.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemCount = ref.watch(wardrobeItemsProvider).value?.length ?? 0;
    final outfitCount = ref.watch(outfitsProvider).value?.length ?? 0;
    final profile = ref.watch(userProfileProvider);
    final account = ref.watch(authSessionProvider).asData?.value;
    return Scaffold(
      appBar: AppBar(title: const Text('个人')),
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
            Card(
              child: Column(
                children: [
                  const ListTile(
                    leading: Icon(Icons.offline_bolt_outlined),
                    title: Text('离线可用'),
                    subtitle: Text('数据与照片保存在本机，不依赖网络'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.cloud_outlined),
                    title: const Text('账号与云同步'),
                    subtitle: const Text('将在后续版本开放'),
                    trailing: const Chip(label: Text('即将推出')),
                    onTap: () {},
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.people_outline),
                    title: const Text('好友与搭配社区'),
                    subtitle: const Text('分享前始终由你确认'),
                    trailing: const Chip(label: Text('即将推出')),
                    onTap: () {},
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Card(
              child: Column(
                children: [
                  const ListTile(
                    leading: Icon(Icons.shield_outlined),
                    title: Text('隐私与数据'),
                    subtitle: Text('本地优先，私有内容默认不上传'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.settings_outlined),
                    title: const Text('设置'),
                    subtitle: const Text('账号、通知、展示与偏好设置'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const _SettingsDetailScreen(),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  const ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('关于叠序'),
                    subtitle: Text('版本 1.0.0 · 本地 MVP'),
                  ),
                ],
              ),
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
      appBar: AppBar(title: const Text('设置')),
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
  final int itemCount;
  final int outfitCount;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0xFF282722),
      borderRadius: BorderRadius.circular(28),
    ),
    child: Stack(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProfileAvatar(path: profile.avatarPath, size: 68),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.nickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    username == null ? 'ID: ${profile.id}' : '@$username',
                    style: const TextStyle(color: Colors.white60),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    profile.signature,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, height: 1.3),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _ProfileStat(value: '$itemCount', label: '件单品'),
                      const SizedBox(width: 26),
                      _ProfileStat(value: '$outfitCount', label: '套搭配'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        Positioned(
          top: -8,
          right: -8,
          child: IconButton(
            tooltip: '编辑个人资料',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, color: Colors.white),
          ),
        ),
      ],
    ),
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
          title: Text('账号：${account.username}'),
          subtitle: Text('已绑定邮箱：${account.email}'),
          trailing: const Chip(label: Text('本地测试')),
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
      subtitle: const Text('衣橱数据仍保留在本机'),
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

  @override
  void dispose() {
    _nickname.dispose();
    _signature.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 512,
    );
    if (image == null) return;
    final path = await ref.read(imageStoreProvider).persist(image);
    if (mounted) setState(() => _avatarPath = path);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(userProfileProvider.notifier)
          .save(
            UserProfile(
              id: widget.profile.id,
              nickname: _nickname.text.trim(),
              signature: _signature.text.trim(),
              avatarPath: _avatarPath,
            ),
          );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('编辑个人资料')),
    body: Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                _ProfileAvatar(path: _avatarPath, size: 104),
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: IconButton.filled(
                    onPressed: _pickAvatar,
                    icon: const Icon(Icons.camera_alt_outlined),
                    tooltip: '更换头像',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          TextFormField(
            controller: _nickname,
            maxLength: 20,
            decoration: const InputDecoration(labelText: '昵称'),
            validator: (value) =>
                value == null || value.trim().isEmpty ? '请输入昵称' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            initialValue: 'ID: ${widget.profile.id}',
            enabled: false,
            decoration: const InputDecoration(labelText: '唯一 ID（不可修改）'),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _signature,
            maxLength: 60,
            maxLines: 3,
            decoration: const InputDecoration(labelText: '个性签名'),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(_saving ? '保存中…' : '保存资料'),
            ),
          ),
        ],
      ),
    ),
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

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({required this.value, required this.label});
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 21,
          fontWeight: FontWeight.bold,
        ),
      ),
      Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
    ],
  );
}
