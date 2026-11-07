import Foundation
import InboxPlusUpdates

let arguments = CommandLine.arguments
guard arguments.count == 4,
      let data = try? Data(contentsOf: URL(fileURLWithPath: arguments[1])),
      UpdateSignature.verify(data: data, publicKey: arguments[2], signature: arguments[3]) else {
    fputs("The update archive does not match the embedded Sparkle public key.\n", stderr)
    exit(1)
}
