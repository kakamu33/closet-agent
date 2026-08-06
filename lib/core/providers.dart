import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/data/cloudbase_auth_repository.dart';
import '../features/auth/domain/auth_repository.dart';
import '../features/auth/domain/auth_user.dart';
import '../features/outfits/data/cloudbase_outfit_repository.dart';
import '../features/outfits/domain/outfit.dart';
import '../features/outfits/domain/outfit_tag.dart';
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
final cloudBaseOutfitRepositoryProvider = Provider<CloudBaseOutfitRepository>(
  (ref) => CloudBaseOutfitRepository(),
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

/// 供需要"仅在已登录且使用 CloudBase 认证时才同步云端"的
/// [AsyncNotifier] 复用：统一获取当前登录用户与其云端 access token。
///
/// 未登录、或当前认证实现并非 [CloudBaseAuthRepository]（例如后续切换为
/// 其他认证方式）时返回 null，调用方据此判断本次操作是否需要触达云端。
mixin CloudSessionMixin<T> on AsyncNotifier<T> {
  Future<CloudSession?> cloudSession() async {
    final user = await ref.read(authSessionProvider.future);
    final repository = ref.read(authRepositoryProvider);
    if (user == null || repository is! CloudBaseAuthRepository) return null;
    final accessToken = await repository.currentAccessToken();
    return accessToken == null ? null : CloudSession(user, accessToken);
  }

  /// 仅在已登录（存在有效 [CloudSession]）时执行 [action]，未登录时静默跳过。
  ///
  /// 用于"本地数据始终为主、云端为登录用户的附加同步"这一类写操作：
  /// 调用方负责本地读写的时机与顺序，这里只负责收敛"要不要触达云端"的
  /// 判断逻辑，避免每个 save/remove 方法里都重复一遍取 session 的样板代码。
  Future<void> syncToCloudIfSignedIn(
    Future<void> Function(CloudSession session) action,
  ) async {
    final session = await cloudSession();
    if (session != null) await action(session);
  }
}

class CloudSession {
  const CloudSession(this.user, this.accessToken);

  final AuthUser user;
  final String accessToken;
}

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

class WardrobeController extends AsyncNotifier<List<WardrobeItem>>
    with CloudSessionMixin {
  AppDatabase get _db => ref.read(databaseProvider);
  CloudBaseWardrobeRepository get _cloud =>
      ref.read(cloudBaseWardrobeRepositoryProvider);

  @override
  Future<List<WardrobeItem>> build() async {
    final localItems = await _db.items();
    final session = await cloudSession();
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
    await syncToCloudIfSignedIn(
      (session) => _cloud.saveItem(
        user: session.user,
        accessToken: session.accessToken,
        item: item,
      ),
    );
    ref.invalidateSelf();
  }

  Future<void> remove(String id) async {
    await syncToCloudIfSignedIn(
      (session) =>
          _cloud.deleteItem(accessToken: session.accessToken, itemId: id),
    );
    await _db.deleteItem(id);
    ref.invalidateSelf();
    ref.invalidate(outfitsProvider);
    ref.invalidate(wardrobeCanvasLayoutsProvider);
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

class WardrobeTagsController extends AsyncNotifier<List<WardrobeTag>>
    with CloudSessionMixin {
  AppDatabase get _db => ref.read(databaseProvider);
  CloudBaseWardrobeRepository get _cloud =>
      ref.read(cloudBaseWardrobeRepositoryProvider);

  @override
  Future<List<WardrobeTag>> build() async {
    final localTags = await _db.tags();
    final session = await cloudSession();
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
  Future<List<WardrobeTag>> _seedDefaultTags(CloudSession session) async {
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

  /// 保存（新增或改名）一个标签。
  ///
  /// 本地写入始终执行；云端同步失败时不阻断本地操作，但会把异常重新
  /// 抛给调用方（UI 层据此提示用户"已保存到本机，云端同步失败"），
  /// 同时避免因为异常提前退出而漏掉 [ref.invalidateSelf]——否则本地
  /// 明明写入成功，界面却因为没有刷新而看起来"毫无变化"。
  Future<void> save(WardrobeTag tag) async {
    final currentTags = await future;
    validateTagName(tag, currentTags);
    await _db.saveTag(tag);
    Object? cloudError;
    try {
      await syncToCloudIfSignedIn(
        (session) => _cloud.saveTag(
          user: session.user,
          accessToken: session.accessToken,
          tag: tag,
          existingTags: currentTags,
        ),
      );
    } catch (error) {
      cloudError = error;
    }
    ref.invalidateSelf();
    if (cloudError != null) throw cloudError;
  }

  Future<void> reorder(List<WardrobeTag> tags) async {
    // ReorderableListView 传来的标签对象仍带着拖拽前的 sortOrder；本地
    // reorderTags 会按列表位置重新编号，但同步云端时也必须发送相同的新值，
    // 否则云端会被旧 sortOrder 覆盖，并在刷新时把本地顺序回滚。
    final reorderedTags = _withUpdatedSortOrders(tags);
    await _db.reorderTags(reorderedTags);
    Object? cloudError;
    try {
      await syncToCloudIfSignedIn(
        (session) => _syncReorderedTags(session, reorderedTags),
      );
    } catch (error) {
      cloudError = error;
    }
    ref.invalidateSelf();
    if (cloudError != null) throw cloudError;
  }

  /// 分两阶段同步排序，避免云端存在 `(user_id, parent_id, sort_order)`
  /// 唯一约束时，交换两个已有位置会在逐条更新的中间状态发生冲突。
  Future<void> _syncReorderedTags(
    CloudSession session,
    List<WardrobeTag> reorderedTags,
  ) async {
    final highestSortOrder = reorderedTags.fold<int>(
      -1,
      (highest, tag) => tag.sortOrder > highest ? tag.sortOrder : highest,
    );
    final temporaryTags = [
      for (var index = 0; index < reorderedTags.length; index++)
        WardrobeTag(
          id: reorderedTags[index].id,
          name: reorderedTags[index].name,
          parentId: reorderedTags[index].parentId,
          sortOrder: highestSortOrder + reorderedTags.length + index + 1,
        ),
    ];
    for (final tag in temporaryTags) {
      await _cloud.saveTag(
        user: session.user,
        accessToken: session.accessToken,
        tag: tag,
        existingTags: temporaryTags,
      );
    }
    for (final tag in reorderedTags) {
      await _cloud.saveTag(
        user: session.user,
        accessToken: session.accessToken,
        tag: tag,
        existingTags: reorderedTags,
      );
    }
  }

  List<WardrobeTag> _withUpdatedSortOrders(List<WardrobeTag> tags) => [
    for (var index = 0; index < tags.length; index++)
      WardrobeTag(
        id: tags[index].id,
        name: tags[index].name,
        parentId: tags[index].parentId,
        sortOrder: index,
      ),
  ];

  Future<void> remove(String id) async {
    Object? cloudError;
    try {
      await syncToCloudIfSignedIn(
        (session) =>
            _cloud.deleteTag(accessToken: session.accessToken, tagId: id),
      );
    } catch (error) {
      cloudError = error;
    }
    await _db.deleteTag(id);
    ref.invalidateSelf();
    ref.invalidate(wardrobeItemsProvider);
    if (cloudError != null) throw cloudError;
  }
}

final outfitTagsProvider =
    AsyncNotifierProvider<OutfitTagsController, List<WardrobeTag>>(
      OutfitTagsController.new,
    );
final outfitsProvider = AsyncNotifierProvider<OutfitController, List<Outfit>>(
  OutfitController.new,
);

class OutfitTagsController extends AsyncNotifier<List<WardrobeTag>>
    with CloudSessionMixin {
  AppDatabase get _db => ref.read(databaseProvider);
  CloudBaseOutfitRepository get _cloud =>
      ref.read(cloudBaseOutfitRepositoryProvider);

  @override
  Future<List<WardrobeTag>> build() async {
    final localTags = await _db.outfitTags();
    final session = await cloudSession();
    if (session == null) return localTags;
    try {
      var cloudTags = await _cloud.fetchTags(
        accessToken: session.accessToken,
      );
      // 新用户首次登录/注册时云端无标签，自动播种默认搭配标签。
      if (cloudTags.isEmpty) {
        cloudTags = await _seedDefaultTags(session);
      }
      // 播种失败时云端仍是空列表——保留本地默认标签缓存，避免把用户能看到
      // 的标签清空；用户下次操作标签（新增/改名）时会自动重新与云端同步。
      if (cloudTags.isEmpty) return localTags;
      await _db.replaceOutfitTags(cloudTags);
      return cloudTags;
    } on CloudBaseException {
      return localTags;
    }
  }

  /// 向云端写入默认搭配标签（确定性 ID，避免重复），并返回写入后的标签列表。
  Future<List<WardrobeTag>> _seedDefaultTags(CloudSession session) async {
    for (final tag in defaultOutfitTags) {
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
        debugPrint('[OutfitTagsController] 播种默认标签 "${tag.name}" 失败: $error');
      }
    }
    try {
      return await _cloud.fetchTags(accessToken: session.accessToken);
    } on CloudBaseException catch (error) {
      debugPrint('[OutfitTagsController] 播种后重新拉取标签失败: $error');
      return const [];
    }
  }

  /// 保存（新增或改名）一个标签。
  ///
  /// 本地写入始终执行；云端同步失败时不阻断本地操作，但会把异常重新
  /// 抛给调用方（UI 层据此提示用户"已保存到本机，云端同步失败"），
  /// 同时避免因为异常提前退出而漏掉 [ref.invalidateSelf]——否则本地
  /// 明明写入成功，界面却因为没有刷新而看起来"毫无变化"。
  Future<void> save(WardrobeTag tag) async {
    final currentTags = await future;
    validateTagName(tag, currentTags);
    await _db.saveOutfitTag(tag);
    Object? cloudError;
    try {
      await syncToCloudIfSignedIn(
        (session) => _cloud.saveTag(
          user: session.user,
          accessToken: session.accessToken,
          tag: tag,
          existingTags: currentTags,
        ),
      );
    } catch (error) {
      cloudError = error;
    }
    ref.invalidateSelf();
    if (cloudError != null) throw cloudError;
  }

  Future<void> reorder(List<WardrobeTag> tags) async {
    // ReorderableListView 传来的标签对象仍带着拖拽前的 sortOrder；本地
    // reorderOutfitTags 会按列表位置重新编号，但同步云端时也必须发送相同的
    // 新值，否则云端会被旧 sortOrder 覆盖，并在刷新时把本地顺序回滚。
    final reorderedTags = _withUpdatedSortOrders(tags);
    await _db.reorderOutfitTags(reorderedTags);
    Object? cloudError;
    try {
      await syncToCloudIfSignedIn(
        (session) => _syncReorderedTags(session, reorderedTags),
      );
    } catch (error) {
      cloudError = error;
    }
    ref.invalidateSelf();
    if (cloudError != null) throw cloudError;
  }

  /// 分两阶段同步排序，避免云端存在 `(user_id, parent_id, sort_order)`
  /// 唯一约束时，交换两个已有位置会在逐条更新的中间状态发生冲突。
  Future<void> _syncReorderedTags(
    CloudSession session,
    List<WardrobeTag> reorderedTags,
  ) async {
    final highestSortOrder = reorderedTags.fold<int>(
      -1,
      (highest, tag) => tag.sortOrder > highest ? tag.sortOrder : highest,
    );
    final temporaryTags = [
      for (var index = 0; index < reorderedTags.length; index++)
        WardrobeTag(
          id: reorderedTags[index].id,
          name: reorderedTags[index].name,
          parentId: reorderedTags[index].parentId,
          sortOrder: highestSortOrder + reorderedTags.length + index + 1,
        ),
    ];
    for (final tag in temporaryTags) {
      await _cloud.saveTag(
        user: session.user,
        accessToken: session.accessToken,
        tag: tag,
        existingTags: temporaryTags,
      );
    }
    for (final tag in reorderedTags) {
      await _cloud.saveTag(
        user: session.user,
        accessToken: session.accessToken,
        tag: tag,
        existingTags: reorderedTags,
      );
    }
  }

  List<WardrobeTag> _withUpdatedSortOrders(List<WardrobeTag> tags) => [
    for (var index = 0; index < tags.length; index++)
      WardrobeTag(
        id: tags[index].id,
        name: tags[index].name,
        parentId: tags[index].parentId,
        sortOrder: index,
      ),
  ];

  Future<void> remove(String id) async {
    Object? cloudError;
    try {
      await syncToCloudIfSignedIn(
        (session) =>
            _cloud.deleteTag(accessToken: session.accessToken, tagId: id),
      );
    } catch (error) {
      cloudError = error;
    }
    await _db.deleteOutfitTag(id);
    ref.invalidateSelf();
    ref.invalidate(outfitsProvider);
    if (cloudError != null) throw cloudError;
  }
}

class OutfitController extends AsyncNotifier<List<Outfit>>
    with CloudSessionMixin {
  AppDatabase get _db => ref.read(databaseProvider);
  CloudBaseOutfitRepository get _cloud =>
      ref.read(cloudBaseOutfitRepositoryProvider);

  @override
  Future<List<Outfit>> build() async {
    final localOutfits = await _db.outfits();
    final session = await cloudSession();
    if (session == null) return localOutfits;
    try {
      final cloudOutfits = await _cloud.fetchOutfits(
        accessToken: session.accessToken,
      );
      await _db.replaceOutfits(cloudOutfits);
      return cloudOutfits;
    } on CloudBaseException {
      // 离线或云端暂不可用时仍可继续使用本地搭配，稍后保存会再次同步。
      return localOutfits;
    }
  }

  Future<void> save(Outfit outfit) async {
    await _db.saveOutfit(outfit);
    await syncToCloudIfSignedIn(
      (session) => _cloud.saveOutfit(
        user: session.user,
        accessToken: session.accessToken,
        outfit: outfit,
      ),
    );
    ref.invalidateSelf();
  }

  Future<void> remove(String id) async {
    await syncToCloudIfSignedIn(
      (session) =>
          _cloud.deleteOutfit(accessToken: session.accessToken, outfitId: id),
    );
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
