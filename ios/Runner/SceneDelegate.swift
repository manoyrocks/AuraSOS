import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    // Launched from the icon's quick-action menu (cold start).
    if let item = connectionOptions.shortcutItem {
      LaunchShortcuts.shared.recordColdStart(item.type)
    }
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }

  override func windowScene(
    _ windowScene: UIWindowScene,
    performActionFor shortcutItem: UIApplicationShortcutItem,
    completionHandler: @escaping (Bool) -> Void
  ) {
    // Quick action tapped while the app is already running.
    LaunchShortcuts.shared.deliver(shortcutItem.type)
    super.windowScene(windowScene, performActionFor: shortcutItem, completionHandler: completionHandler)
  }
}
