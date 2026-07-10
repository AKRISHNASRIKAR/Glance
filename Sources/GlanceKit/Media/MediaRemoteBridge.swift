import Foundation

/// Thin, isolated wrapper around Apple's **private, undocumented**
/// MediaRemote framework — the same framework that powers Control Center's
/// Now Playing widget.
///
/// This is the ONLY way on macOS to observe what's playing in an arbitrary
/// application (browser tabs, VLC, podcast apps, ...). There is no public
/// API for it: `MPNowPlayingInfoCenter` is publish-only, for an app's own
/// media. Every notch-style app that shows system-wide Now Playing
/// (including the "boring.notch" reference this feature is modeled on)
/// relies on this same private framework.
///
/// This is the **only file in the codebase** that intentionally uses a
/// private API, and it is entirely opt-in: nothing here is touched unless
/// the user explicitly enables "System-wide Now Playing (Experimental)" in
/// Settings — see `NowPlayingSettings.enableSystemMediaRemote`.
///
/// Risk, stated plainly: this framework is undocumented, unversioned, and
/// Apple could change or remove it in any macOS release without notice.
/// Every symbol lookup below is nil-checked; if the framework or any
/// required symbol fails to resolve, `isAvailable` is false and the feature
/// reports Unavailable rather than crashing or faking data. The dictionary
/// key names are the widely-used values documented by community
/// reverse-engineering (used identically by several public open-source
/// MediaRemote wrappers); Apple has never published them.
///
/// `MediaRemoteBridge.shared` is a lazy singleton: the private framework is
/// not loaded into the process at all until something actually reads
/// `.shared` — i.e., only after the user opts in.
final class MediaRemoteBridge: @unchecked Sendable {
    static let shared = MediaRemoteBridge()

    private typealias GetNowPlayingInfoFn = @convention(c) (DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void) -> Void
    private typealias RegisterFn = @convention(c) (DispatchQueue) -> Void
    private typealias VoidFn = @convention(c) () -> Void
    private typealias SendCommandFn = @convention(c) (Int32, CFDictionary?) -> Bool
    private typealias GetNowPlayingClientFn = @convention(c) (DispatchQueue, @escaping @convention(block) (AnyObject?) -> Void) -> Void
    private typealias SetWantsNotificationsFn = @convention(c) (Bool) -> Void

    private let getNowPlayingInfoFn: GetNowPlayingInfoFn?
    private let registerFn: RegisterFn?
    private let unregisterFn: VoidFn?
    private let sendCommandFn: SendCommandFn?
    private let getNowPlayingClientFn: GetNowPlayingClientFn?
    /// Without this call, `MRMediaRemoteGetNowPlayingInfo` still answers a
    /// one-off snapshot, but on current macOS the framework never posts
    /// `kMRMediaRemoteNowPlayingInfoDidChangeNotification` afterward — so the
    /// system-wide source would silently freeze on whatever was playing at
    /// launch. Confirmed present via dlsym on this OS; best-effort like
    /// `getNowPlayingClientFn` so its absence degrades rather than disables.
    private let setWantsNotificationsFn: SetWantsNotificationsFn?

    /// True only if every symbol this bridge depends on for basic function
    /// resolved. Callers must check this before use.
    let isAvailable: Bool

    private init() {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_NOW
        ) else {
            getNowPlayingInfoFn = nil
            registerFn = nil
            unregisterFn = nil
            sendCommandFn = nil
            getNowPlayingClientFn = nil
            setWantsNotificationsFn = nil
            isAvailable = false
            return
        }

        func load<T>(_ name: String, as type: T.Type) -> T? {
            guard let sym = dlsym(handle, name) else { return nil }
            return unsafeBitCast(sym, to: T.self)
        }

        getNowPlayingInfoFn = load("MRMediaRemoteGetNowPlayingInfo", as: GetNowPlayingInfoFn.self)
        registerFn = load("MRMediaRemoteRegisterForNowPlayingNotifications", as: RegisterFn.self)
        unregisterFn = load("MRMediaRemoteUnregisterForNowPlayingNotifications", as: VoidFn.self)
        sendCommandFn = load("MRMediaRemoteSendCommand", as: SendCommandFn.self)
        // Best-effort only: used solely to label the source with a real app
        // name. Its absence doesn't disable the feature.
        getNowPlayingClientFn = load("MRMediaRemoteGetNowPlayingClient", as: GetNowPlayingClientFn.self)
        setWantsNotificationsFn = load("MRMediaRemoteSetWantsNowPlayingNotifications", as: SetWantsNotificationsFn.self)

        isAvailable = getNowPlayingInfoFn != nil && registerFn != nil && unregisterFn != nil && sendCommandFn != nil
    }

    /// Posted on the default (in-process) NotificationCenter once registered.
    static let nowPlayingInfoDidChange = Notification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification")

    func register() {
        guard isAvailable else { return }
        registerFn?(.main)
        // Must follow registration: tells MediaRemote this process actually
        // wants change notifications, not just a one-off snapshot.
        setWantsNotificationsFn?(true)
    }

    func unregister() {
        guard isAvailable else { return }
        setWantsNotificationsFn?(false)
        unregisterFn?()
    }

    func getNowPlayingInfo(completion: @escaping (CFDictionary?) -> Void) {
        guard isAvailable, let fn = getNowPlayingInfoFn else {
            completion(nil)
            return
        }
        fn(.main, completion)
    }

    /// Resolves the bundle identifier of the app currently publishing Now
    /// Playing info, via dynamic message send (no header/protocol needed).
    /// Returns nil whenever the symbol is missing or the object doesn't
    /// respond — never a guess.
    func getNowPlayingClientBundleIdentifier(completion: @escaping (String?) -> Void) {
        guard isAvailable, let fn = getNowPlayingClientFn else {
            completion(nil)
            return
        }
        fn(.main) { client in
            guard let object = client as? NSObject,
                  object.responds(to: Self.bundleIdentifierSelector) else {
                completion(nil)
                return
            }
            let result = object.perform(Self.bundleIdentifierSelector)
            completion(result?.takeUnretainedValue() as? String)
        }
    }

    private static let bundleIdentifierSelector = Selector(("bundleIdentifier"))

    enum Command: Int32 {
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
    }

    @discardableResult
    func send(_ command: Command) -> Bool {
        guard isAvailable, let fn = sendCommandFn else { return false }
        return fn(command.rawValue, nil)
    }
}
