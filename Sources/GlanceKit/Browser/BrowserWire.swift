import Foundation
import Darwin

public enum BrowserJSON: Codable, Sendable, Equatable {
    case object([String: BrowserJSON]), array([BrowserJSON]), string(String), number(Double), bool(Bool), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([BrowserJSON].self) { self = .array(v) }
        else { self = .object(try c.decode([String: BrowserJSON].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .object(let v): try c.encode(v); case .array(let v): try c.encode(v); case .string(let v): try c.encode(v); case .number(let v): try c.encode(v); case .bool(let v): try c.encode(v); case .null: try c.encodeNil() }
    }
    public subscript(_ key: String) -> BrowserJSON { if case .object(let v) = self { return v[key] ?? .null }; return .null }
    public var string: String? { if case .string(let v) = self { return v }; return nil }
    public var number: Double? { if case .number(let v) = self { return v }; return nil }
    public static func encode<T: Encodable>(_ value: T) throws -> BrowserJSON { try JSONDecoder().decode(BrowserJSON.self, from: JSONEncoder().encode(value)) }
}
public struct BrowserRequest: Codable, Sendable, Equatable {
    public let protocolVersion: Int
    public let id: String
    public let type: String
    public let clientID: String
    public var payload: BrowserJSON
    public var token: String?
    public var origin: String?
}
public struct BrowserResponse: Codable, Sendable {
    public let id: String
    public let ok: Bool
    public let payload: BrowserJSON?
    public let error: String?
    public init(id: String, payload: BrowserJSON) { self.id=id; self.ok=true; self.payload=payload; self.error=nil }
    public init(id: String, error: String) { self.id=id; self.ok=false; self.payload=nil; self.error=error }
}
public enum BrowserBridgeError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let v) = self { return v }; return nil }
}
public enum BrowserPaths {
    public static var root: URL {
        if let custom = ProcessInfo.processInfo.environment["GLANCE_BROWSER_DIR"] { return URL(fileURLWithPath: custom) }
        return SettingsStore.defaultFileURL().deletingLastPathComponent().appendingPathComponent("Browser", isDirectory:true)
    }
    public static var socketPath: String { root.appendingPathComponent("bridge.sock").path }
}
public enum BrowserSocket {
    public static let limit = 262144
    public static func address(_ path: String) throws -> sockaddr_un {
        var a=sockaddr_un(); a.sun_family=sa_family_t(AF_UNIX)
        let bytes=Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue:a.sun_path) else { throw BrowserBridgeError.message("The browser connection path is too long.") }
        withUnsafeMutableBytes(of:&a.sun_path) { target in for (i,b) in bytes.enumerated() { target[i]=UInt8(bitPattern:b) } }
        a.sun_len=UInt8(MemoryLayout<sockaddr_un>.size); return a
    }
    public static func configure(_ fd:Int32) {
        // Accepted macOS sockets can inherit the nonblocking listener flag.
        _ = fcntl(fd,F_SETFL,fcntl(fd,F_GETFL) & ~O_NONBLOCK)
        var yes:Int32=1; setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&yes,socklen_t(MemoryLayout.size(ofValue:yes)))
        var timeout=timeval(tv_sec:125,tv_usec:0); setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,socklen_t(MemoryLayout.size(ofValue:timeout)))
        setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,socklen_t(MemoryLayout.size(ofValue:timeout)))
    }
    public static func write(_ data:Data,to fd:Int32) throws {
        try data.withUnsafeBytes { bytes in
            var offset=0
            while offset<data.count { let n=Darwin.write(fd,bytes.baseAddress!.advanced(by:offset),data.count-offset); if n<0 && errno==EINTR {continue};guard n>0 else {throw BrowserBridgeError.message("Browser connection write failed.")};offset+=n }
        }
    }
    public static func readLine(_ fd:Int32) throws -> Data {
        var data=Data();var buffer=[UInt8](repeating:0,count:4096)
        while data.count<=limit {
            let n=Darwin.read(fd,&buffer,buffer.count)
            if n<0 && errno==EINTR {continue}
            guard n>0 else {throw BrowserBridgeError.message("The Mac connection closed or timed out.")}
            data.append(contentsOf:buffer.prefix(n))
            if let end=data.firstIndex(of:10) {guard end<=limit else {break};return Data(data[..<end])}
        }
        throw BrowserBridgeError.message("Browser message exceeds the size limit.")
    }
    public static func call(_ request:BrowserRequest,path:String=BrowserPaths.socketPath) throws -> BrowserResponse {
        let fd=Darwin.socket(AF_UNIX,SOCK_STREAM,0);guard fd>=0 else {throw BrowserBridgeError.message("Cannot create the Mac connection.")};defer{Darwin.close(fd)};configure(fd)
        var a=try address(path)
        let result=withUnsafePointer(to:&a) { $0.withMemoryRebound(to:sockaddr.self,capacity:1) {Darwin.connect(fd,$0,socklen_t(MemoryLayout<sockaddr_un>.size))} }
        guard result==0 else {throw BrowserBridgeError.message("Open Glance on your Mac and enable Browser Connection in Settings.")}
        var data=try JSONEncoder().encode(request);data.append(10);try write(data,to:fd)
        return try JSONDecoder().decode(BrowserResponse.self,from:readLine(fd))
    }
}
public final class BrowserSocketServer: @unchecked Sendable {
    private var source: DispatchSourceRead?
    private let path:String
    public init(path:String=BrowserPaths.socketPath) {self.path=path}
    public func start(handler:@escaping @Sendable (BrowserRequest) async -> BrowserResponse) throws {
        let fd=Darwin.socket(AF_UNIX,SOCK_STREAM,0);guard fd>=0 else {throw BrowserBridgeError.message("Cannot create browser socket.")}
        var a=try BrowserSocket.address(path)
        // Do not replace another live app's socket.
        let probe=Darwin.socket(AF_UNIX,SOCK_STREAM,0)
        if probe>=0 {
            let live=withUnsafePointer(to:&a){$0.withMemoryRebound(to:sockaddr.self,capacity:1){Darwin.connect(probe,$0,socklen_t(MemoryLayout<sockaddr_un>.size))}}
            Darwin.close(probe)
            if live==0 {Darwin.close(fd);throw BrowserBridgeError.message("Another Glance browser connection is already running.")}
        }
        var info=stat()
        if lstat(path,&info)==0 {
            guard info.st_uid==getuid(),(info.st_mode & S_IFMT)==S_IFSOCK else {Darwin.close(fd);throw BrowserBridgeError.message("Unsafe existing socket path.")}
            unlink(path)
        }
        let bound=withUnsafePointer(to:&a){$0.withMemoryRebound(to:sockaddr.self,capacity:1){Darwin.bind(fd,$0,socklen_t(MemoryLayout<sockaddr_un>.size))}}
        guard bound==0,chmod(path,0o600)==0,Darwin.listen(fd,8)==0 else {Darwin.close(fd);throw BrowserBridgeError.message("Cannot open the local browser socket.")}
        _ = fcntl(fd,F_SETFL,O_NONBLOCK)
        let source=DispatchSource.makeReadSource(fileDescriptor:fd,queue:DispatchQueue(label:"app.glance.browser.accept"))
        source.setEventHandler {
            while true {
                let peer=Darwin.accept(fd,nil,nil);if peer<0 {break}
                BrowserSocket.configure(peer)
                DispatchQueue.global(qos:.utility).async {
                    var uid:uid_t=0;var gid:gid_t=0
                    guard getpeereid(peer,&uid,&gid)==0,uid==getuid() else {Darwin.close(peer);return}
                    do {
                        let data=try BrowserSocket.readLine(peer)
                        let request=try JSONDecoder().decode(BrowserRequest.self,from:data)
                        Task {
                            let response=await handler(request)
                            if var output=try? JSONEncoder().encode(response) {output.append(10);try? BrowserSocket.write(output,to:peer)}
                            Darwin.close(peer)
                        }
                    } catch {Darwin.close(peer)}
                }
            }
        }
        let socketPath=path;source.setCancelHandler{Darwin.close(fd);unlink(socketPath)};source.resume();self.source=source
    }
    public func stop(){source?.cancel();source=nil}
    deinit{source?.cancel()}
}
