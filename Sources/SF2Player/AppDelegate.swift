import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var windowController: MainWindowController?
    private var pendingFile: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = MainWindowController()
        windowController = controller
        buildMainMenu(target: controller)

        controller.showWindow(nil)
        controller.focusKeyboard()
        NSApp.activate(ignoringOtherApps: true)

        if let url = pendingFile {
            pendingFile = nil
            controller.loadSoundFont(at: url)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowController?.shutdown()
    }

    // Abrir arquivo .sf2 pelo Finder ("Abrir com...") ou arrastando para o ícone.
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        guard url.pathExtension.lowercased() == "sf2" else { return false }
        if let controller = windowController {
            controller.loadSoundFont(at: url)
        } else {
            pendingFile = url
        }
        return true
    }

    // MARK: - Menu principal (em português)

    private func buildMainMenu(target: MainWindowController) {
        let mainMenu = NSMenu()

        // Menu do aplicativo
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Sobre o SF2Player",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Ocultar SF2Player",
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Ocultar Outros",
                                         action: #selector(NSApplication.hideOtherApplications(_:)),
                                         keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Mostrar Tudo",
                        action: #selector(NSApplication.unhideAllApplications(_:)),
                        keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Encerrar SF2Player",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")

        // Menu Arquivo
        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "Arquivo")
        fileItem.submenu = fileMenu
        let openItem = fileMenu.addItem(withTitle: "Abrir SoundFont…",
                                        action: #selector(MainWindowController.openSoundFont(_:)),
                                        keyEquivalent: "o")
        openItem.target = target
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Fechar Janela",
                         action: #selector(NSWindow.performClose(_:)),
                         keyEquivalent: "w")

        // Menu Áudio
        let audioItem = NSMenuItem()
        mainMenu.addItem(audioItem)
        let audioMenu = NSMenu(title: "Áudio")
        audioItem.submenu = audioMenu
        let panicItem = audioMenu.addItem(withTitle: "Panic (All Notes Off)",
                                          action: #selector(MainWindowController.panicAction(_:)),
                                          keyEquivalent: ".")
        panicItem.target = target

        // Menu Janela
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Janela")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimizar",
                           action: #selector(NSWindow.performMiniaturize(_:)),
                           keyEquivalent: "m")

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }
}
