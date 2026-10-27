import Foundation
import Testing
@testable import GlanceKit

@Suite("Browser statistics and protocol")
@MainActor
struct BrowserTests {
    func store() throws -> BrowserStatsStore {try BrowserStatsStore(file:makeTempDirectory().appendingPathComponent("browser.json"))}
    func event(_ sequence:Int,domain:String?="example.com",type:String="usage",seconds:Double=30) -> BrowserStatEvent {
        BrowserStatEvent(id:"client:\(sequence)",sequence:sequence,clientID:"client",type:type,domain:domain,seconds:seconds,at:Date().timeIntervalSince1970*1000,sessionID:nil,outcome:nil)
    }
    @Test func replayDoesNotDuplicateAcknowledgedUsage() throws {
        let s=try store();#expect(try s.ingest([event(1)],clientID:"client")==1);#expect(try s.ingest([event(1)],clientID:"client")==1);#expect(s.summary.sites.first?.seconds==30)
    }
    @Test func purgePreservesCursorSoReconnectCannotResurrectData() throws {
        let s=try store();_ = try s.ingest([event(1)],clientID:"client");try s.purge(clientID:"client",throughSequence:1);_ = try s.ingest([event(1)],clientID:"client");#expect(s.summary.sites.isEmpty);_ = try s.ingest([event(2)],clientID:"client");#expect(s.summary.sites.first?.seconds==30)
    }
    @Test func malformedAndCrossProfileBatchesAreRejected() throws {
        let s=try store()
        #expect(throws:(any Error).self){try s.ingest([event(1,domain:"https://example.com/private?token=secret")],clientID:"client")}
        #expect(throws:(any Error).self){try s.ingest([event(1)],clientID:"another-profile")}
        #expect(throws:(any Error).self){try s.ingest([event(1,seconds:.infinity)],clientID:"client")}
        #expect(throws:(any Error).self){try s.ingest(Array(repeating:event(1),count:101),clientID:"client")}
    }
    @Test func nativeFocusIsNotDuplicated() throws {
        let s=try store();try s.recordNativeFocus(id:"focus-1",seconds:100,outcome:"completed");try s.recordNativeFocus(id:"focus-1",seconds:100,outcome:"completed");#expect(s.summary.completed==1);#expect(s.summary.focusSeconds==100)
    }
    @Test func clearingMacCopyDoesNotDeleteNewImports() throws {
        let s=try store();_ = try s.ingest([event(1)],clientID:"client");try s.clearAll();_ = try s.ingest([event(1),event(2)],clientID:"client");#expect(s.summary.sites.first?.seconds==30)
    }
    @Test func jsonWireRoundTripPreservesEnvelopeAndRejectsBadTypes() throws {
        let raw=Data("{\"protocolVersion\":1,\"id\":\"id\",\"clientID\":\"client\",\"type\":\"snapshot\",\"payload\":{}}".utf8)
        let r=try JSONDecoder().decode(BrowserRequest.self,from:raw);#expect(r.protocolVersion==1)
        let response=BrowserResponse(id:r.id,payload:.object(["value":.number(25)]));let decoded=try JSONDecoder().decode(BrowserResponse.self,from:JSONEncoder().encode(response));#expect(decoded.payload?["value"].number==25)
        #expect(throws:(any Error).self){try JSONDecoder().decode(BrowserRequest.self,from:Data("{}".utf8))}
    }
    @Test func unsafeSocketPathsAreRejected() {#expect(throws:(any Error).self){try BrowserSocket.address(String(repeating:"x",count:200))}}

    @Test func sharedPreferencesPersistAndRejectStaleWrites() throws {
        let file=makeTempDirectory().appendingPathComponent("preferences.json")
        let store=try BrowserPreferencesStore(file:file)
        var value=BrowserFocusPreferences();value.entries=[BrowserDomainPreference(domain:"example.com",subdomains:true,enabled:true)]
        try store.update(value,expectedRevision:0)
        let reloaded=try BrowserPreferencesStore(file:file)
        #expect(reloaded.snapshot.value==value);#expect(reloaded.snapshot.initialized)
        #expect(throws:(any Error).self){try reloaded.update(BrowserFocusPreferences(),expectedRevision:0)}
        #expect((try FileManager.default.attributesOfItem(atPath:file.path)[.posixPermissions] as? NSNumber)?.intValue==0o600)
    }
    @Test func sharedPreferencesRejectURLsAndDuplicateRules() throws {
        var value=BrowserFocusPreferences();value.entries=[BrowserDomainPreference(domain:"https://example.com/private",subdomains:true,enabled:true)]
        #expect(throws:(any Error).self){try BrowserPreferencesStore.validate(value)}
        value.entries=[BrowserDomainPreference(domain:"example.com",subdomains:true,enabled:true),BrowserDomainPreference(domain:"example.com",subdomains:false,enabled:true)]
        #expect(throws:(any Error).self){try BrowserPreferencesStore.validate(value)}
    }
}
