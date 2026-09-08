import Foundation

/// Resolves which Python interpreter runs a given Odoo version, from the
/// explicit per-version list configured in Settings (no assumption about how
/// or where interpreters/virtualenvs are managed) -- falls back to a
/// configured default interpreter, if any, for versions without their own entry.
enum InterpreterResolver {
    static func resolveInterpreter(_ branchOrVersion: String) throws -> String {
        let mappings = Config.interpreters
        if let match = mappings.first(where: { $0.version == branchOrVersion }) {
            return match.path
        }
        // Convenience: "19.0" <-> "19" are often used interchangeably.
        let alternate = branchOrVersion.hasSuffix(".0") ? String(branchOrVersion.dropLast(2)) : branchOrVersion + ".0"
        if let match = mappings.first(where: { $0.version == alternate }) {
            return match.path
        }
        if !Config.defaultInterpreterPath.isEmpty {
            return Config.defaultInterpreterPath
        }
        let known = mappings.map(\.version).sorted().joined(separator: ", ")
        throw ProcessError(message: "No Python interpreter configured for \"\(branchOrVersion)\" (known versions: \(known.isEmpty ? "none" : known)). Add one in Settings → Python Interpreters, or set a default interpreter.")
    }
}
