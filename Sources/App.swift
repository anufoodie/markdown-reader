import SwiftUI
import UniformTypeIdentifiers
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
        for window in NSApp.windows { window.tabbingMode = .preferred }
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        for window in NSApp.windows { window.tabbingMode = .preferred }
    }
}

@main
struct MarkdownReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
        }
        .commands {
            CommandMenu("Review") {
                Button("Toggle Review Mode") {
                    NotificationCenter.default.post(name: .toggleReviewMode, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("Toggle Comments Drawer") {
                    NotificationCenter.default.post(name: .toggleReviewDrawer, object: nil)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Divider()

                Button("Finish Review (Generate Payload)") {
                    NotificationCenter.default.post(name: .finishReview, object: nil)
                }
                .keyboardShortcut(.return, modifiers: [.command])
            }

            CommandGroup(after: .textFormatting) {
                Button("Toggle Editor") {
                    NotificationCenter.default.post(name: .toggleEditor, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command])

                Button("Toggle Sidebar") {
                    NotificationCenter.default.post(name: .toggleTOC, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Divider()

                Button("Find in Document") {
                    NotificationCenter.default.post(name: .findInDocument, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command])

                Button("Quick Open") {
                    NotificationCenter.default.post(name: .quickOpen, object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command])

                Divider()

                Button("Collapse All Sections") {
                    NotificationCenter.default.post(name: .collapseAll, object: nil)
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])

                Button("Expand All Sections") {
                    NotificationCenter.default.post(name: .expandAll, object: nil)
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])

                Divider()

                Button("Increase Font Size") {
                    NotificationCenter.default.post(name: .fontSizeUp, object: nil)
                }
                .keyboardShortcut("+", modifiers: [.command])

                Button("Decrease Font Size") {
                    NotificationCenter.default.post(name: .fontSizeDown, object: nil)
                }
                .keyboardShortcut("-", modifiers: [.command])
            }
        }
    }
}

extension Notification.Name {
    static let toggleEditor     = Notification.Name("toggleEditor")
    static let toggleTOC        = Notification.Name("toggleTOC")
    static let findInDocument   = Notification.Name("findInDocument")
    static let quickOpen        = Notification.Name("quickOpen")
    static let collapseAll      = Notification.Name("collapseAll")
    static let expandAll        = Notification.Name("expandAll")
    static let fontSizeUp       = Notification.Name("fontSizeUp")
    static let fontSizeDown     = Notification.Name("fontSizeDown")
    static let toggleReviewMode = Notification.Name("toggleReviewMode")
    static let toggleReviewDrawer = Notification.Name("toggleReviewDrawer")
    static let finishReview     = Notification.Name("finishReview")
}
