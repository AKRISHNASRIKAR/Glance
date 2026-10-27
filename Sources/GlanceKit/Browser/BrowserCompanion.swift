import Foundation
import Combine

public struct BrowserSessionSnapshot: Codable, Sendable {
    public let id:String?
    public let owner:String
    public let phase:String
    public let state:String
    public let remaining:Double
    public let endAt:Double?
    public let revision:Int
}
public struct BrowserSnapshot: Codable, Sendable {
    public let protocolVersion:Int
    public let epoch:String
    public let session:BrowserSessionSnapshot
    public let stats:BrowserStatsSummary
    public let pomodoro:PomodoroSettings
    public let preferences:BrowserPreferencesSnapshot
}
@MainActor
public final class BrowserCompanion: ObservableObject {
    @Published public private(set) var status="Browser connection is off."
    @Published public private(set) var enabled=false
    @Published public private(set) var connectedProfiles=0
    public let statistics:BrowserStatsStore?
    public let preferences:BrowserPreferencesStore?
    public var approvePairing: @MainActor (String)->Bool = {_ in false}
    private let engine:PomodoroEngine
    private let settings:SettingsStore
    private var server:BrowserSocketServer?
    private var configuration:BrowserConfiguration?
    private var observer:AnyCancellable?
    private let epoch=UUID().uuidString
    private var focusID:String?
    private var accumulated:Double=0
    private var anchor:Date?
    private var revision=0
    private var signature=""
    private var responses:[String:(request:BrowserRequest,response:BrowserResponse)]=[:]
    private var clients:[String:Date]=[:]
    public init(engine:PomodoroEngine,settings:SettingsStore) {
        self.engine=engine;self.settings=settings
        do{statistics=try BrowserStatsStore()}catch{statistics=nil}
        do{preferences=try BrowserPreferencesStore()}catch{preferences=nil}
        observer=engine.$runState.combineLatest(engine.$phase,engine.$remaining).debounce(for:.milliseconds(5),scheduler:RunLoop.main).sink{[weak self] _ in self?.reconcile()}
        let callback=engine.onPhaseCompleted
        engine.onPhaseCompleted={[weak self] phase in callback?(phase);if phase == .focus {self?.finish(outcome:"completed")}}
        if let config=try? BrowserConfiguration.load(),config.enabled {configuration=config;do{try startServer()}catch{status=error.localizedDescription}}
    }
    public func enable(helper:URL) throws {
        guard statistics != nil,preferences != nil else {throw BrowserBridgeError.message("Browser statistics could not be loaded. Check the local statistics file before enabling.")}
        try BrowserInstallation.install(helper:helper)
        configuration=try BrowserConfiguration.load()
        if server==nil{try startServer()}
        status="Ready. Click Connect to Glance in the Chrome extension."
    }
    public func disable() {
        finish(outcome:"interrupted")
        server?.stop();server=nil;enabled=false
        if var c=configuration {c.enabled=false;c.approvedClients=[];try? c.save();configuration=c}
        connectedProfiles=0;status="Browser connection is off."
    }
    public func revokeAll(){configuration?.approvedClients=[];try? configuration?.save();status="Pairing revoked. Approve the extension again to reconnect."}
    public func stop(){finish(outcome:"interrupted");server?.stop();server=nil;enabled=false}
    private func startServer() throws {
        let s=BrowserSocketServer()
        try s.start{[weak self] request in
            guard let self else{return BrowserResponse(id:request.id,error:"Glance is shutting down.")}
            return await self.handle(request)
        }
        server=s;enabled=true;status="Waiting for a browser connection."
    }
    private func finish(outcome:String) {
        guard let id=focusID else{return}
        if let a=anchor {accumulated+=max(0,Date().timeIntervalSince(a))}
        do{try statistics?.recordNativeFocus(id:id,seconds:accumulated,outcome:outcome)}catch{status="Statistics could not be saved: \(error.localizedDescription)"}
        focusID=nil;anchor=nil;accumulated=0
    }
    private func reconcile() {
        guard enabled else{return}
        if engine.phase == .focus,engine.runState != .idle {
            if focusID==nil {focusID=UUID().uuidString;accumulated=0}
            if engine.runState == .running,anchor==nil {anchor=Date()}
            if engine.runState == .paused,let a=anchor {accumulated+=max(0,Date().timeIntervalSince(a));anchor=nil}
        }else if focusID != nil {finish(outcome:engine.phase == .focus ? "interrupted":"completed")}
        let key="\(focusID ?? "idle")|\(engine.phase)|\(engine.runState)|\(engine.scheduledEndDate?.timeIntervalSince1970 ?? 0)|\(engine.runState == .paused ? engine.remaining:0)"
        if key != signature {signature=key;revision+=1}
    }
    public func snapshot() throws -> BrowserSnapshot {
        engine.updateConfiguration(settings.settings.pomodoro);engine.tick();reconcile()
        guard let stats=statistics,let preferences else{throw BrowserBridgeError.message("Browser statistics are unavailable.")}
        return BrowserSnapshot(protocolVersion:1,epoch:epoch,session:BrowserSessionSnapshot(id:focusID,owner:"mac",phase:engine.phase == .focus ? "focus":engine.phase == .shortBreak ? "shortBreak":"longBreak",state:engine.runState.rawValue,remaining:engine.remaining*1000,endAt:engine.scheduledEndDate.map{$0.timeIntervalSince1970*1000},revision:revision),stats:stats.summary,pomodoro:settings.settings.pomodoro,preferences:preferences.snapshot)
    }
    public func handle(_ request:BrowserRequest) -> BrowserResponse {
        do {
            guard request.protocolVersion==1 else{throw BrowserBridgeError.message("Incompatible bridge protocol. Update Glance and the extension.")}
            guard let c=configuration,c.enabled,request.token==c.token,let origin=request.origin,c.allowedOrigins.contains(origin),UUID(uuidString:request.clientID) != nil,UUID(uuidString:request.id) != nil else{throw BrowserBridgeError.message("Browser authentication failed.")}
            if request.type=="pair" {
                if !c.approvedClients.contains(request.clientID) {
                    guard approvePairing(request.clientID) else{throw BrowserBridgeError.message("Pairing was not approved in Glance.")}
                    configuration?.approvedClients.append(request.clientID);try configuration?.save()
                }
            }else{guard c.approvedClients.contains(request.clientID) else{throw BrowserBridgeError.message("Click Connect and approve this browser profile in Glance.")}}
            clients[request.clientID]=Date();clients=clients.filter{Date().timeIntervalSince($0.value)<15};connectedProfiles=clients.count
            status="Connected to \(connectedProfiles) browser profile(s)."
            let requestKey="\(request.clientID)/\(request.id)"
            if let cached=responses[requestKey] {
                guard cached.request==request else{throw BrowserBridgeError.message("A request ID was reused with a different command.")}
                return cached.response
            }
            let payload:BrowserJSON
            switch request.type {
            case "pair","snapshot":payload=try BrowserJSON.encode(snapshot())
            case "timer":
                reconcile()
                guard request.payload["expectedRevision"].number==Double(revision) else{throw BrowserBridgeError.message("The Mac timer changed. Refresh before trying again.")}
                switch request.payload["action"].string {
                case "start":
                    guard engine.runState == .idle else{throw BrowserBridgeError.message("End the current Mac session first.")}
                    // Start the Mac's selected phase/configuration. A browser dropdown never changes it.
                    engine.updateConfiguration(settings.settings.pomodoro);engine.start()
                case "pause":guard engine.runState == .running else{throw BrowserBridgeError.message("The timer is not running.")};engine.pause()
                case "resume":guard engine.runState == .paused else{throw BrowserBridgeError.message("The timer is not paused.")};engine.resume()
                case "stop":finish(outcome:"interrupted");engine.reset()
                default:throw BrowserBridgeError.message("Unsupported timer action.")
                }
                payload=try BrowserJSON.encode(snapshot())
            case "preferences":
                guard let preferences,let revision=request.payload["expectedRevision"].number,revision.isFinite,revision>=0,revision<Double(Int.max),revision.rounded()==revision else{throw BrowserBridgeError.message("Invalid settings revision.")}
                let value=try JSONDecoder().decode(BrowserFocusPreferences.self,from:JSONEncoder().encode(request.payload["value"]))
                try preferences.update(value,expectedRevision:Int(revision))
                payload=try BrowserJSON.encode(snapshot())
            case "pomodoroSettings":
                let expected=try JSONDecoder().decode(PomodoroSettings.self,from:JSONEncoder().encode(request.payload["expected"]))
                let value=try JSONDecoder().decode(PomodoroSettings.self,from:JSONEncoder().encode(request.payload["value"]))
                guard expected==settings.settings.pomodoro else{throw BrowserBridgeError.message("Pomodoro settings changed on the Mac. Refresh and try again.")}
                guard [value.focusDuration,value.shortBreakDuration,value.longBreakDuration].allSatisfy({$0.isFinite && $0>=60 && $0<=7200}),value.sessionsBeforeLongBreak>=1,value.sessionsBeforeLongBreak<=12,!value.durationPresetsMinutes.isEmpty,value.durationPresetsMinutes.count<=12,value.durationPresetsMinutes.allSatisfy({$0>=1 && $0<=120}) else {throw BrowserBridgeError.message("Use durations of 1–120 minutes, 1–12 sessions and up to 12 presets.")}
                settings.update{$0.pomodoro=value};settings.saveNow();engine.updateConfiguration(value)
                payload=try BrowserJSON.encode(snapshot())
            case "stats":
                guard let stats=statistics,case .array(let values)=request.payload["events"] else{throw BrowserBridgeError.message("Invalid statistics batch.")}
                let events=try JSONDecoder().decode([BrowserStatEvent].self,from:JSONEncoder().encode(values))
                payload = .object(["ack":.number(Double(try stats.ingest(events,clientID:request.clientID)))])
            case "purgeStats":
                guard let n=request.payload["throughSequence"].number,n>=0,n<Double(Int.max),n.rounded()==n else{throw BrowserBridgeError.message("Invalid deletion cursor.")}
                try statistics?.purge(clientID:request.clientID,throughSequence:Int(n));payload = .object(["cleared":.bool(true)])
            default:throw BrowserBridgeError.message("Unsupported browser command.")
            }
            let result=BrowserResponse(id:request.id,payload:payload)
            if request.type=="timer" || request.type=="purgeStats" {if responses.count>=256{responses.removeAll()};responses[requestKey]=(request,result)}
            return result
        }catch{return BrowserResponse(id:request.id,error:error.localizedDescription)}
    }
}
