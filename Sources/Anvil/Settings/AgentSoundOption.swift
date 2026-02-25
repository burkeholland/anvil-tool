import Foundation

/// Keys used to store user preferences in UserDefaults.
enum UserDefaultsKeys {
    static let playSoundOnAgentFinish = "playSoundOnAgentFinish"
    static let agentFinishSoundName = "agentFinishSoundName"
    static let showNotificationOnAgentFinish = "showNotificationOnAgentFinish"
}

/// The set of curated macOS system sounds available in Anvil's settings.
enum AgentSoundOption: String, CaseIterable, Identifiable {
    case basso = "Basso"
    case blow = "Blow"
    case bottle = "Bottle"
    case frog = "Frog"
    case funk = "Funk"
    case glass = "Glass"
    case hero = "Hero"
    case morse = "Morse"
    case ping = "Ping"
    case pop = "Pop"
    case purr = "Purr"
    case sosumi = "Sosumi"
    case submarine = "Submarine"
    case tink = "Tink"

    var id: String { rawValue }
}
