import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    // super で Flutter window が確立された後に背景色を設定。
    // edge-to-edge 表示時にステータスバー / ホームインジケーター領域が
    // 黒く露出しないよう、UIWindow と rootViewController.view を
    // アプリ背景色 (#FFFFFF, AppColors.bg) で塗る。
    if let window = self.window {
      window.backgroundColor = UIColor.white
      window.rootViewController?.view.backgroundColor = UIColor.white
    }

    return result
  }
}
