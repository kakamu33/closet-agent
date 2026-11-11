# 叠序 / closet-agent

Flutter 衣橱应用，使用 Riverpod、SQLite / Web localStorage、CloudBase Auth 与 PostgreSQL。
支持衣物、搭配、标签、自由画布和服务端抠图。当前没有大模型 Agent 执行模块。

## 本地运行

1. 使用 `.fvmrc` 指定的 Flutter stable（项目要求 Dart >= 3.12.2）。
2. 将 `.env.example` 复制为 `.env`，填写自己的 CloudBase 环境和私有图片 Bucket。
3. `flutter pub get`
4. `flutter run -d chrome`，或使用 iOS / Android / macOS 设备。

`.env` 会作为公开客户端资源打包，只能放公开配置。Poof Key 必须配置在云函数环境中。
本地没有配置 Bucket 时，修改仍会保存在本机，图片同步会明确显示待重试。

## 架构与部署

- [架构和同步约定](docs/architecture.md)
- [云端部署与验收](docs/deployment.md)
- [数据库事务及引用清理迁移](database/migrations/001_sync_integrity.sql)
- [业务与存储所有权策略](database/migrations/002_owner_policies.sql)

## 检查

```sh
flutter analyze
flutter test
flutter build web
node --test test/cloudfunctions/functions.test.cjs
```

回归测试覆盖离线保存/删除、崩溃恢复、慢网络并发编辑、账号隔离、布局保留、
认证刷新、图片编辑生命周期、分页，以及云函数的鉴权与日志脱敏。
测试使用本地 SQLite 和模拟 HTTP，不连接生产 CloudBase。
