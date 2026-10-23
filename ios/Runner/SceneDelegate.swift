import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
    for context in contexts { AppDelegate.receive(context.url) }
    super.scene(scene, openURLContexts: contexts)
  }
  override func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    for context in connectionOptions.urlContexts { AppDelegate.receive(context.url) }
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }
}
