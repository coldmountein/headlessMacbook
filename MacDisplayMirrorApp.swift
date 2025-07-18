import SwiftUI
import Cocoa
import Foundation
import CoreGraphics

struct DisplayInfo {
    let id: String
    let type: String
    let resolution: String
    let raw: String // displayplacer 推荐命令的原始参数
}

@main
struct MacDisplayMirrorAppApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var displayplacerURL: URL? {
        Bundle.main.url(forResource: "displayplacer", withExtension: "bin")
    }
    var allDisplays: [DisplayInfo] = []
    var allDisplayRawParams: [String] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.title = "🖥️"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "一键镜像", action: #selector(mirrorNow), keyEquivalent: "m"))
        menu.addItem(NSMenuItem.separator())
        // 动态添加所有显示器菜单项
        updateDisplayMenuItems(menu: menu)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu

        // 启动时自动镜像
        mirrorNow()
    }

    func updateDisplayMenuItems(menu: NSMenu) {
        // 获取所有显示器信息
        guard let displayplacerURL = displayplacerURL else { return }
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: displayplacerURL.path)
        let process = Process()
        process.executableURL = displayplacerURL
        process.arguments = ["list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                // 解析所有显示器
                let (displays, rawParams) = parseAllDisplaysAndRawParams(from: output)
                self.allDisplays = displays
                self.allDisplayRawParams = rawParams
                for (idx, display) in displays.enumerated() {
                    let title = "\(display.type) \(display.resolution)"
                    let item = NSMenuItem(title: title, action: #selector(setAsMainDisplay(_:)), keyEquivalent: "")
                    item.representedObject = idx // 用索引定位
                    menu.addItem(item)
                }
            }
        } catch {
            print("displayplacer list 失败: \(error)")
        }
    }

    // 一键镜像
    @objc func mirrorNow() {
        guard let displayplacerURL = displayplacerURL else {
            showAlert(title: "错误", message: "找不到 displayplacer 可执行文件")
            return
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: displayplacerURL.path)

        let process = Process()
        process.executableURL = displayplacerURL
        process.arguments = ["list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                if let (internalId, externalId) = parseDisplayIds(from: output) {
                    let mirrorArgs = ["id:\(internalId)+\(externalId) mirror:true"]
                    let mirrorProcess = Process()
                    mirrorProcess.executableURL = displayplacerURL
                    mirrorProcess.arguments = mirrorArgs
                    do {
                        try mirrorProcess.run()
                        mirrorProcess.waitUntilExit()
                    } catch {
                        showAlert(title: "错误", message: "设置镜像失败: \(error)")
                    }
                } else {
                    showAlert(title: "错误", message: "未能自动识别内外屏id，请检查 displayplacer 输出。")
                }
            }
        } catch {
            showAlert(title: "错误", message: "运行 displayplacer 失败: \(error)")
        }
    }

    // 用户点击某个显示器菜单项，将其设为主显示器
    @objc func setAsMainDisplay(_ sender: NSMenuItem) {
        guard let idx = sender.representedObject as? Int else { return }
        guard let displayplacerURL = displayplacerURL else { return }
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: displayplacerURL.path)

        // 重新排列 origin
        var newScreens = allDisplayRawParams
        // 先将选中的设为 (0,0)
        newScreens[idx] = replaceOrigin(in: newScreens[idx], with: "(0,0)")
        // 其余依次排列
        var currentX = 0
        if let width = extractWidth(from: newScreens[idx]) {
            currentX = width
        }
        for (i, screen) in allDisplayRawParams.enumerated() {
            if i != idx {
                newScreens[i] = replaceOrigin(in: screen, with: "(\(currentX),0)")
                if let width = extractWidth(from: screen) {
                    currentX += width
                }
            }
        }
        print("即将执行的参数：\(newScreens)")
        // 执行新命令
        let mainProcess = Process()
        mainProcess.executableURL = displayplacerURL
        mainProcess.arguments = newScreens
        do {
            try mainProcess.run()
            mainProcess.waitUntilExit()
        } catch {
            showAlert(title: "错误", message: "设置主显示器失败: \(error)")
        }
    }

    // 解析所有显示器信息和 displayplacer 推荐参数
    func parseAllDisplaysAndRawParams(from output: String) -> ([DisplayInfo], [String]) {
        let lines = output.components(separatedBy: "\n")
        var displays: [DisplayInfo] = []
        var currentId: String?
        var currentType: String?
        var currentRes: String?
        for line in lines {
            if line.contains("Persistent screen id:") {
                currentId = line.components(separatedBy: "Persistent screen id:").last?.trimmingCharacters(in: .whitespaces)
            }
            if line.contains("Type:") {
                currentType = line.components(separatedBy: "Type:").last?.trimmingCharacters(in: .whitespaces)
            }
            if line.contains("Resolution:") {
                currentRes = line.components(separatedBy: "Resolution:").last?.trimmingCharacters(in: .whitespaces)
            }
            if let id = currentId, let type = currentType, let res = currentRes {
                displays.append(DisplayInfo(id: id, type: type, resolution: res, raw: ""))
                currentId = nil
                currentType = nil
                currentRes = nil
            }
        }
        // 解析 displayplacer 推荐命令
        var rawParams: [String] = []
        if let commandLine = lines.last(where: { $0.contains("displayplacer ") }) {
            let pattern = "\"([^\"]+)\""
            let regex = try! NSRegularExpression(pattern: pattern, options: [])
            let matches = regex.matches(in: commandLine, options: [], range: NSRange(location: 0, length: commandLine.utf16.count))
            rawParams = matches.compactMap {
                if let range = Range($0.range(at: 1), in: commandLine) {
                    return String(commandLine[range])
                }
                return nil
            }
        }
        // 保证顺序一致
        for i in 0..<min(displays.count, rawParams.count) {
            displays[i] = DisplayInfo(id: displays[i].id, type: displays[i].type, resolution: displays[i].resolution, raw: rawParams[i])
        }
        return (displays, rawParams)
    }

    // 解析内外屏 id（用于镜像）
    func parseDisplayIds(from output: String) -> (String, String)? {
        let lines = output.components(separatedBy: "\n")
        var internalId: String?
        var externalId: String?
        var lastId: String?
        for line in lines {
            if line.contains("Persistent screen id:") {
                if let id = line.components(separatedBy: "Persistent screen id:").last?.trimmingCharacters(in: .whitespaces) {
                    lastId = id
                }
            }
            if line.contains("Type:") {
                if line.lowercased().contains("built in screen") || line.lowercased().contains("built-in") {
                    internalId = lastId
                } else if line.lowercased().contains("external screen") || line.lowercased().contains("external") {
                    externalId = lastId
                }
            }
        }
        if let i = internalId, let e = externalId {
            return (i, e)
        }
        return nil
    }

    func replaceOrigin(in screen: String, with newOrigin: String) -> String {
        let pattern = "origin:\\([^\\)]+\\)"
        if let range = screen.range(of: pattern, options: .regularExpression) {
            return screen.replacingCharacters(in: range, with: "origin:\(newOrigin)")
        }
        return screen
    }

    func extractWidth(from screen: String) -> Int? {
        let pattern = "res:(\\d+)x\\d+"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           let match = regex.firstMatch(in: screen, options: [], range: NSRange(location: 0, length: screen.utf16.count)),
           let range = Range(match.range(at: 1), in: screen) {
            return Int(screen[range])
        }
        return nil
    }

    func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    @objc func quit() {
        NSApplication.shared.terminate(self)
    }
} 