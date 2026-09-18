import Foundation
import Testing

/// Standalone entry point for the providers suite, mirroring what `swift test`
/// does for Swift Testing binaries (`__swiftPMEntryPoint` is the library's public
/// runner): needed because this suite is compiled with `swiftc`, not Xcode.
@main
enum ProvidersTestMain {
    static func main() async {
        exit(await Testing.__swiftPMEntryPoint(passing: nil))
    }
}
