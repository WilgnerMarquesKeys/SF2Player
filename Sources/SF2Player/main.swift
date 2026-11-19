import AppKit

// Ponto de entrada do aplicativo (sem storyboard/xib, tudo em código).
let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.regular)
application.run()
