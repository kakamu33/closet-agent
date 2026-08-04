import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/data/cloudbase_auth_repository.dart';
import '../features/auth/domain/auth_repository.dart';
import '../features/auth/domain/auth_user.dart';
import '../features/outfits/domain/outfit.dart';
import '../features/settings/domain/user_profile.dart';
import '../features/wardrobe/data/background_removal_service.dart';
import '../features/wardrobe/data/cloudbase_wardrobe_repository.dart';
import '../features/wardrobe/data/image_store.dart';
import '../features/wardrobe/domain/wardrobe_canvas_layout.dart';
import '../features/wardrobe/domain/wardrobe_canvas_region.dart';
import '../features/wardrobe/domain/wardrobe_item.dart';
import '../features/wardrobe/domain/wardrobe_tag.dart';
import 'cloudbase/cloudbase_client.dart';
import 'database/app_database.dart';

final databaseProvider = Provider<AppDatabase>((ref) => AppDatabase());
final imageStoreProvider = Provider<ImageStore>((ref) => const ImageStore());
final cloudBaseWardrobeRepositoryProvider =
    Provider<CloudBaseWardrobeRepository>(
      (ref) => CloudBaseWardrobeRepository(),
    );
final backgroundRemovalServiceProvider = Provider<BackgroundRemovalService>(
  (ref) => const BackgroundRemovalService(),
);

/// CloudBase 认证负责账户密码、邮箱验证码与登录令牌；密码不会保存到设备。
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => CloudBaseAuthRepository(),
);
final authSessionProvider =
    AsyncNotifierProvider<AuthSessionController, AuthUser?>(
      AuthSessionController.new,
    );

final userProfileProvider =
    AsyncNotifierProvider<UserProfileController, UserProfile>(
      UserProfileController.new,
    );
final wardrobeItemsProvider =
    AsyncNotifierProvider<WardrobeController, List<WardrobeItem>>(
      WardrobeController.new,
    );
final wardrobeTagsProvider =
    AsyncNotifierProvider<WardrobeTagsController, List<WardrobeTag>>(
      WardrobeTagsController.new,
    );
final wardrobeCanvasLayoutsProvider =
    AsyncNotifierProvider<
      WardrobeCanvasLayoutsController,
      List<WardrobeCanvasLayout>
    >(WardrobeCanvasLayoutsController.new);
final wardrobeCanvasRegionsProvider =
    AsyncNotifierProvider<
      WardrobeCanvasRegionsController,
      List<WardrobeCanvasRegion>
    >(WardrobeCanvasRegionsController.new);
final wardrobeCanvasShowNamesProvider =
    AsyncNotifierProvider<WardrobeCanvasShowNamesController, bool>(
      WardrobeCanvasShowNamesController.new,
    );

class AuthSessionController extends AsyncNotifier<AuthUser?> {
  AuthRepository get _repository => ref.read(authRepositoryProvider);

  @override
  Future<AuthUser?> build() async {
    final repository = _repository;
    if (repository is CloudBaseAuthRepository &&
        await repository.clearLegacyLocalAuthArtifacts()) {
      await ref.read(databaseProvider).clearLocalData();
    }
    return repository.currentUser();
  }

  /// 仅在认证成功后更新会话，避免提交期间卸载登录页面。
  Future<AuthUser> register({
    required String username,
    required String nickname,
    required String email,
    required String password,
    required String verificationId,
    required String verificationCode,
  }) async {
    final user = await _repository.register(
      username: username,
      nickname: nickname,
      email: email,
      password: password,
      verificationId: verificationId,
      verificationCode: verificationCode,
    );
    await _resetLocalCache();
    state = AsyncData(user);
    _invalidateLocalDataProviders();
    return user;
  }

  /// 认证失败时将异常交给界面展示，成功后才跳转至主界面。
  Future<AuthUser> login({
    required String identifier,
    required String password,
  }) async {
    final user = await _repository.login(
      identifier: identifier,
      password: password,
    );
    await _resetLocalCache();
    state = AsyncData(user);
    _invalidateLocalDataProviders();
    return user;
  }

  Future<void> logout() async {
    await _repository.logout();
    await _resetLocalCache();
    state = const AsyncData(null);
    _invalidateLocalDataProviders();
  }

  /// 永久注销当前账号（登录凭证与全部业务数据一并删除，不可恢复）；
  /// 无论云端删除是否完全成功，本机缓存都会被清空并回到未登录状态。
  Future<void> deleteAccount() async {
    try {
      await _repository.deleteAccount();
    } finally {
      await _resetLocalCache();
      state = const AsyncData(null);
      _invalidateLocalDataProviders();
    }
  }

  Future<void> _resetLocalCache() =>
      ref.read(databaseProvider).clearLocalData();

  void _invalidateLocalDataProviders() {
    ref.invalidate(userProfileProvider);
    ref.invalidate(wardrobeItemsProvider);
    ref.invalidate(wardrobeTagsProvider);
    ref.invalidate(wardrobeCanvasLayoutsProvider);
    ref.invalidate(wardrobeCanvasRegionsProvider);
    ref.invalidate(wardrobeCanvasShowNamesProvider);
    ref.invalidate(outfitTagsProvider);
    ref.invalidate(outfitsProvider);
  }
}

class UserProfileController extends AsyncNotifier<UserProfile> {
  AppDatabase get _db => ref.read(databaseProvider);
  @override
  Future<UserProfile> build() => _db.profile();
  Future<void> save(UserProfile profile) async {
    await _db.saveProfile(profile);
    ref.invalidateSelf();
  }
}

class WardrobeController extends AsyncNotifier<List<WardrobeItem>> {
  AppDatabase get _db => ref.read(databaseProvider);
  CloudBaseWardrobeRepository get _cloud =>
      ref.read(cloudBaseWardrobeRepositoryProvider);

  @override
  Future<List<WardrobeItem>> build() async {
    final localItems = await _db.items();
    final session = await _cloudSession();
    if (session == null) return localItems;
    try {
      final cloudItems = await _cloud.fetchItems(
        accessToken: session.accessToken,
      );
      await _db.replaceItems(cloudItems);
      return cloudItems;
    } on CloudBaseException {
      // 离线或云端暂不可用时仍可继续使用本地衣橱，稍后保存会再次同步。
      return localItems;
    }
  }

  Future<void> save(WardrobeItem item) async {
    await _db.saveItem(item);
    final session = await _cloudSession();
    if (session != null) {
      await _cloud.saveItem(
        user: session.user,
        accessToken: session.accessToken,
        item: item,
      );
    }
    ref.invalidateSelf();
  }

  Future<void> remove(String id) async {
    final session = await _cloudSession();
    if (session != null) {
      await _cloud.deleteItem(accessToken: session.accessToken, itemId: id);
    }
    await _db.deleteItem(id);
    ref.invalidateSelf();
    ref.invalidate(outfitsProvider);
    ref.invalidate(wardrobeCanvasLayoutsProvider);
  }

  Future<_CloudSession?> _cloudSession() async {
    final user = await ref.read(authSessionProvider.future);
    final repository = ref.read(authRepositoryProvider);
    if (user == null || repository is! CloudBaseAuthRepository) return null;
    final accessToken = await repository.currentAccessToken();
    return accessToken == null ? null : _CloudSession(user, accessToken);
  }
}

class WardrobeCanvasRegionsController
    extends AsyncNotifier<List<WardrobeCanvasRegion>> {
  AppDatabase get _db => ref.read(databaseProvider);

  @override
  Future<List<WardrobeCanvasRegion>> build() => _db.canvasRegions();

  Future<void> save(WardrobeCanvasRegion region) async {
    await _db.saveCanvasRegion(region);
    final current = state is AsyncData<List<WardrobeCanvasRegion>>
        ? (state as AsyncData<List<WardrobeCanvasRegion>>).value
        : const <WardrobeCanvasRegion>[];
    state = AsyncData([
      ...current.where((entry) => entry.id != region.id),
      region,
    ]);
  }

  Future<void> remove(String id) async {
    await _db.deleteCanvasRegion(id);
    final current = state is AsyncData<List<WardrobeCanvasRegion>>
        ? (state as AsyncData<List<WardrobeCanvasRegion>>).value
        : const <WardrobeCanvasRegion>[];
    state = AsyncData(current.where((entry) => entry.id != id).toList());
  }
}

class WardrobeCanvasShowNamesController extends AsyncNotifier<bool> {
  AppDatabase get _db => ref.read(databaseProvider);

  @override
  Future<bool> build() => _db.canvasShowNames();

  Future<void> save(bool showNames) async {
    await _db.saveCanvasShowNames(showNames);
    state = AsyncData(showNames);
  }
}

class WardrobeCanvasLayoutsController
    extends AsyncNotifier<List<WardrobeCanvasLayout>> {
  AppDatabase get _db => ref.read(databaseProvider);

  @override
  Future<List<WardrobeCanvasLayout>> build() => _db.canvasLayouts();

  Future<void> save(WardrobeCanvasLayout layout) async {
    await _db.saveCanvasLayout(layout);
    final current = state is AsyncData<List<WardrobeCanvasLayout>>
        ? (state as AsyncData<List<WardrobeCanvasLayout>>).value
        : const <WardrobeCanvasLayout>[];
    state = AsyncData([
      ...current.where((entry) => entry.itemId != layout.itemId),
      layout,
    ]);
  }
}

class WardrobeTagsController extends AsyncNotifier<List<WardrobeTag>> {
  AppDatabase get _db => ref.read(databaseProvider);
  CloudBaseWardrobeRepository get _cloud =>
      ref.read(cloudBaseWardrobeRepositoryProvider);

  @override
  Future<List<WardrobeTag>> build() async {
    final localTags = await _db.tags();
    final session = await _cloudSession();
    if (session == null) return localTags;
    try {
      var cloudTags = await _cloud.fetchTags(
        accessToken: session.accessToken,
      );
      // 新用户首次登录/注册时云端无标签，自动播种默认标签
      if (cloudTags.isEmpty) {
        cloudTags = await _seedDefaultTags(session);
      }
      // 播种失败时云端仍是空列表——保留本地默认标签缓存，避免把用户能看到
      // 的标签清空；用户下次操作标签（新增/改名）时会自动重新与云端同步。
      if (cloudTags.isEmpty) return localTags;
      await _db.replaceTags(cloudTags);
      return cloudTags;
    } on CloudBaseException {
      return localTags;
    }
  }

  /// 向云端写入默认标签（确定性 ID，避免重复），并返回写入后的标签列表。
  Future<List<WardrobeTag>> _seedDefaultTags(_CloudSession session) async {
    for (final tag in defaultWardrobeTags) {
      try {
        await _cloud.saveTag(
          user: session.user,
          accessToken: session.accessToken,
          tag: tag,
          existingTags: const [],
        );
      } on CloudBaseException catch (error) {
        // 播种失败不阻断：用户可后续手动添加标签；打印出来便于排查，
        // 避免云端接口出问题时完全没有任何痕迹可查。
        debugPrint('[WardrobeTagsController] 播种默认标签 "${tag.name}" 失败: $error');
      }
    }
    try {
      return await _cloud.fetchTags(accessToken: session.accessToken);
    } on CloudBaseException catch (error) {
      debugPrint('[WardrobeTagsController] 播种后重新拉取标签失败: $error');
      return const [];
    }
  }

  Future<void> save(WardrobeTag tag) async {
    final currentTags = await future;
    validateTagName(tag, currentTags);
    await _db.saveTag(tag);
    final session = await _cloudSession();
    if (session != null) {
      await _cloud.saveTag(
        user: session.user,
        accessToken: session.accessToken,
        tag: tag,
        existingTags: currentTags,
      );
    }
    ref.invalidateSelf();
  }

  Future<void> reorder(List<WardrobeTag> tags) async {
    await _db.reorderTags(tags);
    final session = await _cloudSession();
    if (session != null) {
      for (final tag in tags) {
        await _cloud.saveTag(
          user: session.user,
          accessToken: session.accessToken,
          tag: tag,
          existingTags: tags,
        );
      }
    }
    ref.invalidateSelf();
  }

  Future<void> remove(String id) async {
    final session = await _cloudSession();
    if (session != null) {
      await _cloud.deleteTag(accessToken: session.accessToken, tagId: id);
    }
    await _db.deleteTag(id);
    ref.invalidateSelf();
    ref.invalidate(wardrobeItemsProvider);
  }

  Future<_CloudSession?> _cloudSession() async {
    final user = await ref.read(authSessionProvider.future);
    final repository = ref.read(authRepositoryProvider);
    if (user == null || repository is! CloudBaseAuthRepository) return null;
    final accessToken = await repository.currentAccessToken();
    return accessToken == null ? null : _CloudSession(user, accessToken);
  }
}

class _CloudSession {
  const _CloudSession(this.user, this.accessToken);

  final AuthUser user;
  final String accessToken;
}

final outfitTagsProvider =
    AsyncNotifierProvider<OutfitTagsController, List<WardrobeTag>>(
      OutfitTagsController.new,
    );
final outfitsProvider = AsyncNotifierProvider<OutfitController, List<Outfit>>(
  OutfitController.new,
);

class OutfitTagsController extends AsyncNotifier<List<WardrobeTag>> {
  AppDatabase get _db => ref.read(databaseProvider);
  @override
  Future<List<WardrobeTag>> build() => _db.outfitTags();
  Future<void> save(WardrobeTag tag) async {
    await _db.saveOutfitTag(tag);
    ref.invalidateSelf();
  }

  Future<void> reorder(List<WardrobeTag> tags) async {
    await _db.reorderOutfitTags(tags);
    ref.invalidateSelf();
  }

  Future<void> remove(String id) async {
    await _db.deleteOutfitTag(id);
    ref.invalidateSelf();
    ref.invalidate(outfitsProvider);
  }
}

class OutfitController extends AsyncNotifier<List<Outfit>> {
  AppDatabase get _db => ref.read(databaseProvider);
  @override
  Future<List<Outfit>> build() => _db.outfits();
  Future<void> save(Outfit outfit) async {
    await _db.saveOutfit(outfit);
    ref.invalidateSelf();
  }

  Future<void> remove(String id) async {
    await _db.deleteOutfit(id);
    ref.invalidateSelf();
  }
}

final itemOutfitsProvider = FutureProvider.family<List<Outfit>, String>((
  ref,
  id,
) async {
  final outfits = await ref.watch(outfitsProvider.future);
  return outfits
      .where((outfit) => outfit.entries.any((entry) => entry.itemId == id))
      .toList();
});
