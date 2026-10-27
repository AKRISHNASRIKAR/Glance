import Foundation
import Combine

public struct BrowserStatEvent: Codable, Sendable, Equatable {
    public let id:String
    public let sequence:Int
    public let clientID:String
    public let type:String
    public let domain:String?
    public let seconds:Double
    public let at:Double
    public let sessionID:String?
    public let outcome:String?
}
public struct BrowserSiteTotal: Codable, Sendable { public let domain:String;public let seconds:Double }
public struct BrowserStatsSummary: Codable, Sendable {
    public let focusSeconds:Double
    public let completed:Int
    public let interrupted:Int
    public let blocked:Int
    public let sites:[BrowserSiteTotal]
}
@MainActor
public final class BrowserStatsStore: ObservableObject {
    private struct Storage:Codable {var schemaVersion=1;var events:[BrowserStatEvent]=[];var acknowledgements:[String:Int]=[:]}
    private var value=Storage()
    private let file:URL
    @Published public private(set) var summary=BrowserStatsSummary(focusSeconds:0,completed:0,interrupted:0,blocked:0,sites:[])
    public init(file:URL=BrowserPaths.root.appendingPathComponent("statistics.json")) throws {
        self.file=file
        if FileManager.default.fileExists(atPath:file.path){value=try JSONDecoder().decode(Storage.self,from:Data(contentsOf:file));guard value.schemaVersion==1 else{throw BrowserBridgeError.message("Unsupported browser statistics version.")}}
        refresh()
    }
    public func ingest(_ events:[BrowserStatEvent],clientID:String,now:Date=Date()) throws -> Int {
        guard events.count<=100 else{throw BrowserBridgeError.message("Statistics batch is too large.")}
        var copy=value;var ack=copy.acknowledgements[clientID] ?? 0
        for e in events.sorted(by:{$0.sequence<$1.sequence}) {
            guard e.clientID==clientID,e.sequence>0,e.id=="\(clientID):\(e.sequence)",["usage","focus","blocked"].contains(e.type),e.seconds.isFinite,e.seconds>=0,e.seconds<=7200,e.at.isFinite,e.at<=now.timeIntervalSince1970*1000+300000 else{throw BrowserBridgeError.message("Invalid statistics event.")}
            if e.type=="usage" || e.type=="blocked" {
                guard let d=e.domain,Self.validDomain(d) else{throw BrowserBridgeError.message("Only domain-level statistics are accepted.")}
            }
            if e.sequence<=ack {continue}
            if e.at>=now.addingTimeInterval(-30*86400).timeIntervalSince1970*1000 {copy.events.append(e)}
            ack=e.sequence
        }
        copy.acknowledgements[clientID]=ack;value=copy;try persist();refresh();return ack
    }
    public func recordNativeFocus(id:String,seconds:Double,outcome:String) throws {
        guard !value.events.contains(where:{$0.sessionID==id && $0.type=="focus"}) else{return}
        let seq=(value.acknowledgements["mac"] ?? 0)+1
        _ = try ingest([BrowserStatEvent(id:"mac:\(seq)",sequence:seq,clientID:"mac",type:"focus",domain:nil,seconds:min(max(seconds,0),7200),at:Date().timeIntervalSince1970*1000,sessionID:id,outcome:outcome)],clientID:"mac")
    }
    public func purge(clientID:String,throughSequence:Int) throws {
        guard throughSequence>=0 else{throw BrowserBridgeError.message("Invalid deletion cursor.")}
        value.events.removeAll{$0.clientID==clientID};value.acknowledgements[clientID]=max(value.acknowledgements[clientID] ?? 0,throughSequence);try persist();refresh()
    }
    public func clearAll() throws {value.events=[];try persist();refresh()}
    public static func validDomain(_ value:String)->Bool {
        value.count<=253 && value.contains(".") && value==value.lowercased() && value.range(of:"^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$",options:.regularExpression) != nil && !value.contains("..") && value != "localhost"
    }
    private func persist() throws {
        value.events=value.events.filter{$0.at>=Date().addingTimeInterval(-30*86400).timeIntervalSince1970*1000}
        value.events=Array(value.events.suffix(50000))
        try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try JSONEncoder().encode(value).write(to:file,options:.atomic);try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
    }
    private func refresh() {
        let recent=value.events.filter{$0.at>=Date().addingTimeInterval(-30*86400).timeIntervalSince1970*1000}
        var sites:[String:Double]=[:];var focus=0.0;var completed=0;var interrupted=0;var blocked=0
        // Mirrored sessions never arrive as browser-owned focus events; still dedupe session IDs across clients.
        var sessions=Set<String>()
        for e in recent {
            if e.type=="usage",let d=e.domain {sites[d,default:0]+=e.seconds}
            if e.type=="blocked" {blocked+=1}
            if e.type=="focus",sessions.insert(e.sessionID ?? e.id).inserted {focus+=e.seconds;if e.outcome=="completed"{completed+=1}else{interrupted+=1}}
        }
        summary=BrowserStatsSummary(focusSeconds:focus,completed:completed,interrupted:interrupted,blocked:blocked,sites:sites.map{BrowserSiteTotal(domain:$0.key,seconds:$0.value)}.sorted{$0.seconds>$1.seconds})
    }
}
