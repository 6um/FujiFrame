import Foundation
import ImageIO
import UniformTypeIdentifiers

@main struct SmartQA {
    static func main() async throws {
        let root = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let inputs = root.appendingPathComponent("Inputs"); try FileManager.default.createDirectory(at:inputs,withIntermediateDirectories:true)
        let lib = try PhotoLibrary(root:root.appendingPathComponent("Library"),create:true)
        let recipe = Recipe(name:"日光配方 · 合成测试",summary:"供智能导入验收，非真实相机样片")
        _ = try await lib.saveRecipe(recipe,parameters:["film":"CLASSIC CHROME","wb":"日光","wbR":"0","wbB":"0"],firmware:"",exposureAdvice:"",note:"旧版")
        _ = try await lib.saveRecipe(recipe,parameters:["film":"CLASSIC CHROME","wb":"日光","wbR":"2","wbB":"-3"],firmware:"",exposureAdvice:"",note:"最新版")
        _ = try await lib.saveRecipe(Recipe(name:"黑白配方 · 合成测试"),parameters:["film":"ACROS + R","wb":"日光","wbR":"2","wbB":"-3"],firmware:"",exposureAdvice:"",note:"")
        for i in 1...4 {
            let context = CGContext(data:nil,width:600,height:400,bitsPerComponent:8,bytesPerRow:2400,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
            context.setFillColor(CGColor(red:Double(i)*0.18,green:0.55,blue:0.45,alpha:1)); context.fill(CGRect(x:0,y:0,width:600,height:400))
            context.setFillColor(CGColor(red:0.9,green:0.8,blue:0.5,alpha:1)); context.fillEllipse(in:CGRect(x:70*i,y:150,width:130,height:130))
            let url = inputs.appendingPathComponent("QA_\(i).jpg")
            let dest = CGImageDestinationCreateWithURL(url as CFURL,UTType.jpeg.identifier as CFString,1,nil)!
            CGImageDestinationAddImage(dest,context.makeImage()!,nil); guard CGImageDestinationFinalize(dest) else { throw FrameError("fixture failed") }
            if i <= 2 {
                var tags = FujiFixture.daylight
                if i == 2 { tags[0x1003] = [0x501] }
                try FujiFixture.inject(tags,into:url)
            }
        }
        print(root.path)
    }
}
