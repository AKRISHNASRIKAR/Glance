import AppKit
import GlanceKit
import SwiftUI

struct BrowserPane:View {
    @EnvironmentObject var browser:BrowserCompanion
    @State private var error:String?
    var body:some View {
        VStack(alignment:.leading,spacing:18){
            SettingsHeader(title:"Browser Focus")
            Text("Pair Glance Focus in Chrome with this Mac. Timers and domain-level activity stay local; no signup is required.").foregroundStyle(.secondary)
            GroupBox {
                VStack(alignment:.leading,spacing:12){
                    Label(browser.status,systemImage:browser.enabled ? "checkmark.shield":"globe")
                    HStack {
                        Button(browser.enabled ? "Repair browser connection":"Enable browser connection"){
                            do {
                                guard let helper=Bundle.main.url(forAuxiliaryExecutable:"GlanceBrowserBridge") else {throw BrowserBridgeError.message("Build and open the app bundle with make app to include the browser helper.")}
                                try browser.enable(helper:helper);error=nil
                            }catch{self.error=error.localizedDescription}
                        }
                        if browser.enabled {Button("Disable"){browser.disable()}}
                    }
                    if browser.enabled {Button("Revoke paired profiles"){browser.revokeAll()}}
                    Text("Development extension ID: \(BrowserDevelopment.extensionID)").font(.caption).textSelection(.enabled)
                    Text("After loading the unpacked Chrome extension, click Connect to Glance and approve its pairing dialog here. This development helper is ad-hoc signed; it is not a notarized public installer.").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity,alignment:.leading).padding(6)
            }
            if let error {Text(error).foregroundStyle(.red).accessibilityLabel("Browser connection error: \(error)")}
            if let preferences=browser.preferences {BrowserPreferencesView(store:preferences)}
            if let store=browser.statistics {BrowserSummaryView(store:store)}
        }
    }
}
private struct BrowserSummaryView:View {
    @ObservedObject var store:BrowserStatsStore
    @State private var clear=false
    @State private var error:String?
    var body:some View {
        GroupBox("Local activity · last 30 days") {
            VStack(alignment:.leading,spacing:12){
                HStack(spacing:24){metric("Focus",value:"\(Int(store.summary.focusSeconds/60))m");metric("Completed",value:"\(store.summary.completed)");metric("Blocked visits",value:"\(store.summary.blocked)")}
                if store.summary.sites.isEmpty {Text("No website usage has arrived yet. Enable usage stats in the extension, then browse while Chrome is focused.").foregroundStyle(.secondary)}
                ForEach(store.summary.sites.prefix(12),id:\.domain){site in HStack{Text(site.domain);Spacer();Text("\(Int(site.seconds/60))m").monospacedDigit()}}
                Text("Profiles are combined here; simultaneous activity in separate profiles is summed, not unique wall-clock time. The Chrome extension remains the owner of browser observations.").font(.caption).foregroundStyle(.secondary)
                Button("Clear Mac copy",role:.destructive){clear=true}.confirmationDialog("Clear the Mac statistics copy? Browser profiles retain their own local history. Existing acknowledged events will not be imported again.",isPresented:$clear){Button("Clear Mac copy",role:.destructive){do{try store.clearAll()}catch{self.error=error.localizedDescription}}}
                if let error{Text(error).foregroundStyle(.red)}
            }.frame(maxWidth:.infinity,alignment:.leading).padding(6)
        }
    }
    func metric(_ title:String,value:String)->some View{VStack(alignment:.leading){Text(value).font(.title2).monospacedDigit();Text(title).font(.caption).foregroundStyle(.secondary)}}
}

private struct BrowserPreferencesView:View {
    @ObservedObject var store:BrowserPreferencesStore
    @State private var error:String?
    var body:some View {
        GroupBox("Shared browser settings · saved on this Mac") {
            VStack(alignment:.leading,spacing:12) {
                Toggle("Website usage tracking",isOn:Binding(get:{store.snapshot.value.tracking},set:{value in change{$0.tracking=value}}))
                Text("Each browser must approve its own website and usage permissions. Paired profiles automatically adopt these settings.").font(.caption).foregroundStyle(.secondary)
                if store.snapshot.value.entries.isEmpty {Text("No blocked websites yet. Add a website in the extension or web dashboard.").foregroundStyle(.secondary)}
                ForEach(store.snapshot.value.entries,id:\.domain){entry in
                    HStack {
                        Toggle(entry.domain,isOn:Binding(get:{store.snapshot.value.entries.first(where:{$0.domain==entry.domain})?.enabled ?? false},set:{enabled in change{value in if let i=value.entries.firstIndex(where:{$0.domain==entry.domain}){value.entries[i].enabled=enabled}}}))
                        Button("Remove"){change{$0.entries.removeAll(where:{$0.domain==entry.domain})}}
                    }
                }
                if let error {Text(error).foregroundStyle(.red)}
            }.frame(maxWidth:.infinity,alignment:.leading).padding(6)
        }
    }
    func change(_ mutate:(inout BrowserFocusPreferences)->Void){var value=store.snapshot.value;mutate(&value);do{try store.update(value,expectedRevision:store.snapshot.revision);error=nil}catch{self.error=error.localizedDescription}}
}
