import SQLKit
import Vapor

struct RecipientsController: Sendable {
    @Sendable func list(_ request: Request) async throws -> RecipientsResponse {
        let user = try request.auth.require(AuthenticatedUser.self)
        let rows = try await request.sql.select().column("*").from("recipients")
            .where("userId", .equal, user.id)
            .orderBy("name")
            .all(decoding: RecipientRow.self)
        return RecipientsResponse(recipients: rows.map(RecipientDTO.init))
    }
}
