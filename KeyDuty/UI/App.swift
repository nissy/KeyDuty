import SwiftUI

@main
struct KeyDutyApp: App {
    @NSApplicationDelegateAdaptor(MenuBarApp.self) private var appDelegate

    // 設定画面はメニューバーから MenuBarApp.showPreferences で開く。
    // App は最低1つの Scene を要求するため、開く経路のない空の Settings を置く
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
