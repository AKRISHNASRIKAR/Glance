import Foundation
import Combine

public struct BrowserDomainPreference: Codable, Equatable, Sendable {
    public var domain:String
    public var subdomains:Bool
    public var enabled:Bool
}
public struct BrowserFocusPreferences: Codable, Equatable, Sendable {
    public var entries:[BrowserDomainPreference]=[]
    public var tracking=false
    public var exclusions:[String]=[]
    public init() {}
}
public struct BrowserPreferencesSnapshot: Codable, Sendable {
    public var initialized=false
    public var revision=0
    public var value=BrowserFocusPreferences()
}
@MainActor
public final class BrowserPreferencesStore: ObservableObject {
    @Published public private(set) var snapshot:BrowserPreferencesSnapshot
    private let file:URL
    public init(file:URL=BrowserPaths.root.appendingPathComponent("focus-preferences.json")) throws {
        self.file=file
        if FileManager.default.fileExists(atPath:file.path) {
            snapshot=try JSONDecoder().decode(BrowserPreferencesSnapshot.self,from:Data(contentsOf:file))
            try Self.validate(snapshot.value)
        }else{snapshot=BrowserPreferencesSnapshot()}
    }
    public static func validate(_ value:BrowserFocusPreferences) throws {
        func domain(_ s:String)->Bool {
            let labels=s.split(separator:".",omittingEmptySubsequences:false)
            return s.count<=253 && s==s.lowercased() && labels.count>=2
                && !s.allSatisfy({$0.isNumber || $0=="."})
                && labels.allSatisfy { label in
                    !label.isEmpty && label.count<=63 && label.first != "-" && label.last != "-"
                        && label.allSatisfy {$0.isASCII && ($0.isLetter || $0.isNumber || $0=="-")}
                }
        }
        guard value.entries.count<=100,value.exclusions.count<=100,Set(value.entries.map(\.domain)).count==value.entries.count,Set(value.exclusions).count==value.exclusions.count,value.entries.allSatisfy({domain($0.domain)}),value.exclusions.allSatisfy(domain) else {throw BrowserBridgeError.message("Invalid browser preferences. Use unique public domains, up to 100 entries.")}
    }
    public func update(_ value:BrowserFocusPreferences,expectedRevision:Int) throws {
        guard expectedRevision==snapshot.revision else {throw BrowserBridgeError.message("Browser settings changed on the Mac. Refresh and try again.")}
        try Self.validate(value)
        let next=BrowserPreferencesSnapshot(initialized:true,revision:snapshot.revision+1,value:value)
        try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try JSONEncoder().encode(next).write(to:file,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
        snapshot=next
    }
}
