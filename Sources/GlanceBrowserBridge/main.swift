import Foundation
import GlanceKit

// stdout is reserved for length-prefixed native messages, never diagnostics.
func exact(_ count:Int) throws -> Data? {
    var result=Data()
    while result.count<count {
        guard let chunk=try FileHandle.standardInput.read(upToCount:count-result.count),!chunk.isEmpty else {
            if result.isEmpty{return nil};throw BrowserBridgeError.message("Incomplete native message.")
        }
        result.append(chunk)
    }
    return result
}
func respond(_ value:BrowserResponse) throws {
    let data=try JSONEncoder().encode(value);var length=UInt32(data.count).littleEndian
    try withUnsafeBytes(of:&length){try FileHandle.standardOutput.write(contentsOf:Data($0))};try FileHandle.standardOutput.write(contentsOf:data)
}
if CommandLine.arguments.contains("--install") {
    do {
        let index=CommandLine.arguments.firstIndex(of:"--extension-id")
        let id=index.flatMap{CommandLine.arguments.indices.contains($0+1) ? CommandLine.arguments[$0+1]:nil} ?? BrowserDevelopment.extensionID
        try BrowserInstallation.install(helper:URL(fileURLWithPath:CommandLine.arguments[0]),extensionID:id)
        FileHandle.standardError.write(Data("Glance host installed. Open Glance, then Connect in the extension.\n".utf8))
    }catch{FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8));exit(1)}
}else{
    do {
        let config=try BrowserConfiguration.load()
        guard CommandLine.arguments.count>1,config.allowedOrigins.contains(CommandLine.arguments[1]) else {throw BrowserBridgeError.message("This extension origin is not allowed.")}
        while let header=try exact(4) {
            let size=header.enumerated().reduce(UInt32(0)){$0 | UInt32($1.element) << (8*$1.offset)}
            guard size>0,size<=BrowserSocket.limit,let data=try exact(Int(size)) else {throw BrowserBridgeError.message("Invalid message size.")}
            var request=try JSONDecoder().decode(BrowserRequest.self,from:data)
            request.token=config.token;request.origin=CommandLine.arguments[1]
            do{try respond(BrowserSocket.call(request))}catch{try respond(BrowserResponse(id:request.id,error:error.localizedDescription))}
        }
    }catch{FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8));exit(1)}
}
