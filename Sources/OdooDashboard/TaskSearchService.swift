import AppKit
import Foundation

/// Drives a search directly off `keyboard`'s persistent search* state (not
/// local view @State) so an in-flight search -- and its eventual result --
/// survives the panel being closed and reopened mid-search, same reasoning
/// as WorktreeStore.submitCreate.
enum TaskSearchService {
    @MainActor
    static func search(_ keyboard: KeyboardController) {
        let trimmed = keyboard.searchQuery.trimmingCharacters(in: .whitespaces)
        let screenshot = keyboard.searchScreenshot
        guard !(trimmed.isEmpty && screenshot == nil), let projectId = Config.taskSearchProjectId, !keyboard.searchIsSearching else { return }

        keyboard.searchIsSearching = true
        keyboard.searchError = nil
        Task {
            let screenshotPath = screenshot.flatMap(saveScreenshot)
            do {
                let tasks = try await OdooTaskClient.searchTasks(projectId: projectId, includeClosed: keyboard.searchIncludeClosed)
                keyboard.searchResults = try await TaskSearchMatcher.match(query: trimmed, in: tasks, screenshotPath: screenshotPath)
            } catch let e as ProcessError {
                keyboard.searchError = e.message
                keyboard.searchResults = []
            } catch {
                keyboard.searchError = error.localizedDescription
                keyboard.searchResults = []
            }
            keyboard.searchHasSearched = true
            keyboard.searchIsSearching = false
        }
    }

    /// Writes the pasted screenshot to a fixed path (overwritten each
    /// search) so Claude can be pointed at a real file to Read.
    private static func saveScreenshot(_ image: NSImage) -> String? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        try? FileManager.default.createDirectory(at: Config.dataDir, withIntermediateDirectories: true)
        guard (try? png.write(to: Config.taskSearchScreenshotPath)) != nil else { return nil }
        return Config.taskSearchScreenshotPath.path
    }
}
