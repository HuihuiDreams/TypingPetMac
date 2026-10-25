import Darwin
import Foundation

// macOS ignores cursor changes from an app that is not frontmost, and the pet and Todo panels never make
// this app frontmost. Without this, hovering a Todo title shows the arrow until the panel is clicked.
// The WindowServer connection property below is undocumented. It is looked up at run time, so if a future
// macOS removes it, nothing fails: the pointer keeps the arrow until a panel is key, as before.
enum BackgroundCursor {
    private typealias DefaultConnection = @convention(c) () -> UInt32
    private typealias SetConnectionProperty = @convention(c) (UInt32, UInt32, CFString, CFTypeRef) -> Int32

    @discardableResult
    static func enable() -> Bool {
        guard let handle = dlopen(nil, RTLD_NOW),
              let connectionSymbol = dlsym(handle, "_CGSDefaultConnection"),
              let setSymbol = dlsym(handle, "CGSSetConnectionProperty") else { return false }
        let connection = unsafeBitCast(connectionSymbol, to: DefaultConnection.self)()
        let setProperty = unsafeBitCast(setSymbol, to: SetConnectionProperty.self)
        return setProperty(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue) == 0
    }
}
