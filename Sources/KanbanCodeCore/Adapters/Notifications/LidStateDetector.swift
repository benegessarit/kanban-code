import Foundation
import IOKit

/// Detects whether the MacBook lid (clamshell) is closed via IOKit.
/// Works even when Amphetamine or similar tools keep the system awake.
public enum LidStateDetector {
    public static var isLidClosed: Bool {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain")
        )
        guard service != MACH_PORT_NULL else { return false }
        defer { IOObjectRelease(service) }

        let key: CFString = "AppleClamshellState" as CFString
        guard let prop = IORegistryEntryCreateCFProperty(
            service, key, kCFAllocatorDefault, 0
        )?.takeRetainedValue() else {
            return false
        }

        // Value is CFBoolean (bridged to NSNumber), compare as Int for safety
        if let num = prop as? Int {
            return num != 0
        }
        return (prop as? Bool) ?? false
    }
}
