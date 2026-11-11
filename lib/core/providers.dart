// Compatibility barrel. Dependencies, application state and synchronization
// live in separate modules; existing screens can migrate imports gradually.
export 'dependencies.dart';
export 'sync/sync_providers.dart';
export '../features/auth/application/auth_controller.dart';
export '../features/settings/application/profile_controller.dart';
export '../features/wardrobe/application/canvas_controllers.dart';
export '../features/wardrobe/application/wardrobe_controllers.dart';
export '../features/outfits/application/outfit_controllers.dart';
