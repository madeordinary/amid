import Foundation

/// Independent reviewed constants; imported manifests and caller hashes cannot enroll a server.
public enum SupportedServerBuilds {
    public static let darkHTTPDSourceCommit = "3075d35e1d2deb65ed8b079137c4ae1213de4b48"
    public static let darkHTTPDSHA256 = "c7c78d329a49f96044f513ab5a4d4acb08ac5f10eae98e49946370e8db7320e4"
    public static let darkHTTPDCodeDirectoryHash = "465b0edd621f1d6b7f1a7914d51e574088ecbef3"

    /// Cheap UI affordance only. This does not authorize a stop or establish server intent.
    public static func canReview(executablePath: String) -> Bool {
        URL(fileURLWithPath: executablePath).lastPathComponent == "darkhttpd"
    }
    public static func reviewedDarkHTTPD(executablePath: String, projectRoot: String) -> TrustedServerAdapter {
        TrustedServerAdapter(reviewedExecutable: executablePath, projectRoot: projectRoot)
    }
}
