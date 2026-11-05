import Foundation
import ScreenplayDomain

/// Pure classification of generation jobs whose submission may have reached
/// the provider but whose result is not stored locally. It never treats these
/// as failed or safe to retry and never changes the persistent job ledger.
enum ProductionImageUncertainSubmission {
    static func isUnresolved(
        _ job: GenerationJobRecord,
        hasPreservedImage: Bool
    ) -> Bool {
        job.capability == .image &&
        job.target.kind == .board &&
        job.request.parameters["workflow"] == "production_image_from_approved_board" &&
        job.status == .running &&
        job.consentedAt != nil &&
        job.submittedAt != nil &&
        job.completedAt == nil &&
        !hasPreservedImage
    }

    static let guidance =
        "This request was submitted, but ScreenplayOS has no verified local result. " +
        "It may still be processing, may have completed remotely, or may have incurred a charge. " +
        "Check your provider account or usage history using the submission time before deciding what to do. " +
        "ScreenplayOS will not retry it automatically."
}
