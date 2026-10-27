import Foundation
import Security

public struct BrowserConfiguration: Codable, Sendable {
    public var enabled:Bool
    public var token:String
    public var allowedOrigins:[String]
    public var approvedClients:[String]
    public static var fileURL:URL {BrowserPaths.root.appendingPathComponent("connection.json")}
    public static func load() throws -> BrowserConfiguration {
        let attrs=try FileManager.default.attributesOfItem(atPath:fileURL.path)
        guard (attrs[.ownerAccountID] as? NSNumber)?.uint32Value==getuid(),((attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o077 == 0 else {throw BrowserBridgeError.message("Browser connection credentials must belong to you and have mode 600.")}
        return try JSONDecoder().decode(Self.self,from:Data(contentsOf:fileURL))
    }
    public func save() throws {
        try FileManager.default.createDirectory(at:BrowserPaths.root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:BrowserPaths.root.path)
        try JSONEncoder().encode(self).write(to:Self.fileURL,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:Self.fileURL.path)
    }
    public static func create(origin:String) throws -> BrowserConfiguration {
        var bytes=[UInt8](repeating:0,count:32)
        guard SecRandomCopyBytes(kSecRandomDefault,bytes.count,&bytes)==errSecSuccess else {throw BrowserBridgeError.message("Could not create pairing credentials.")}
        let c=Self(enabled:true,token:Data(bytes).base64EncodedString(),allowedOrigins:[origin],approvedClients:[]);try c.save();return c
    }
}
public enum BrowserInstallation {
    public static func install(helper:URL,extensionID:String=BrowserDevelopment.extensionID,manifestDirectories:[URL]?=nil) throws {
        guard extensionID.count==32,extensionID.allSatisfy({("a"..."p").contains(String($0))}) else {throw BrowserBridgeError.message("Invalid extension ID.")}
        let origin="chrome-extension://\(extensionID)/"
        var config:BrowserConfiguration
        if FileManager.default.fileExists(atPath:BrowserConfiguration.fileURL.path){config=try BrowserConfiguration.load()}else{config=try BrowserConfiguration.create(origin:origin)}
        config.enabled=true;try config.save()
        if !config.allowedOrigins.contains(origin){config.allowedOrigins.append(origin);try config.save()}
        let destination=BrowserPaths.root.appendingPathComponent("GlanceBrowserBridge")
        if helper.standardizedFileURL != destination.standardizedFileURL {
            let stage=BrowserPaths.root.appendingPathComponent("helper-\(UUID().uuidString)")
            try FileManager.default.copyItem(at:helper,to:stage)
            try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:stage.path)
            if FileManager.default.fileExists(atPath:destination.path){_ = try FileManager.default.replaceItemAt(destination,withItemAt:stage)}else{try FileManager.default.moveItem(at:stage,to:destination)}
        }
        let manifest:[String:Any]=["name":BrowserDevelopment.hostName,"description":"Glance local browser connection","path":destination.path,"type":"stdio","allowed_origins":config.allowedOrigins]
        let home=FileManager.default.homeDirectoryForCurrentUser
        let dirs=manifestDirectories ?? ["Google/Chrome","Google/ChromeForTesting","Chromium"].map{home.appendingPathComponent("Library/Application Support/\($0)/NativeMessagingHosts")}
        for dir in dirs {try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);try JSONSerialization.data(withJSONObject:manifest,options:.prettyPrinted).write(to:dir.appendingPathComponent("\(BrowserDevelopment.hostName).json"),options:.atomic)}
    }
}
