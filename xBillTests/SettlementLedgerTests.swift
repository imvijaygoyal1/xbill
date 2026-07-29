import Foundation
import Testing
@testable import xBill

@Suite("Settlement row coding")
struct SettlementCodingTests {

    @Test("Decodes the PostgREST row shape")
    func decodesRow() throws {
        let id = UUID(), group = UUID(), from = UUID(), to = UUID(), by = UUID()
        let json = """
        {"id":"\(id.uuidString)","group_id":"\(group.uuidString)",
         "from_user_id":"\(from.uuidString)","to_user_id":"\(to.uuidString)",
         "amount":10.5,"currency":"USD","recorded_by":"\(by.uuidString)",
         "created_at":"2026-07-28T12:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let s = try decoder.decode(Settlement.self, from: Data(json.utf8))

        #expect(s.id == id)
        #expect(s.groupID == group)
        #expect(s.fromUserID == from)
        #expect(s.toUserID == to)
        #expect(s.amount == Decimal(string: "10.5"))
        #expect(s.recordedBy == by)
    }

    /// `Settlement.PaymentMethod` is used by PaymentLinkService and ProfileView.
    /// Replacing the struct must not remove it.
    @Test("PaymentMethod is still reachable")
    func paymentMethodSurvives() {
        #expect(Settlement.PaymentMethod.paypal.rawValue == "paypal")
        #expect(Settlement.PaymentMethod.venmo.rawValue == "venmo")
    }
}
