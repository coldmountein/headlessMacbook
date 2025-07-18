import Cocoa
import CoreGraphics

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // 创建菜单栏图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.title = "🖥️"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "手动镜像", action: #selector(mirrorNow), keyEquivalent: "m"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu

        // 启动时自动镜像
        mirrorNow()
    }

    @objc func mirrorNow() {
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetActiveDisplayList(displayCount, &displays, &displayCount)

        var internalDisplay: CGDirectDisplayID?
        var externalDisplay: CGDirectDisplayID?

        for d in displays {
            if CGDisplayIsBuiltin(d) != 0 {
                internalDisplay = d
            } else {
                externalDisplay = d
            }
        }

        if let internalDisplay = internalDisplay, let externalDisplay = externalDisplay {
            let err = CGDisplayMirrorDisplay(externalDisplay, internalDisplay)
            if err == .success {
                print("已设置镜像显示")
            } else {
                print("设置镜像失败：\(err)")
            }
        } else {
            print("未检测到内外屏")
        }
    }

    @objc func quit() {
        NSApplication.shared.terminate(self)
    }
} 