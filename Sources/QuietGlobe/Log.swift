import os

/// Shared logger for the app. Messages are visible in Console.app and `log show`.
let logger = Logger(subsystem: "io.github.prakunin.quietglobe", category: "app")

func log(_ message: String) {
    logger.info("\(message, privacy: .public)")
}
