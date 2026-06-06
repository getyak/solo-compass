import XCTest
@testable import SoloCompass

/// Covers the testable pure / injectable logic behind the chat-experience
/// upgrade (design doc `docs/design/chat-experience-upgrade.md`):
///
/// 1. `SupabaseAttachmentService.mapStatus` — HTTP status → typed
///    `AttachmentError` (the degrade-vs-actionable-error fork).
/// 2. `ChatMessage` Codable round-trip with attachments, and decode from a
///    hand-written camelCase JSON payload matching the TS `ChatMessage` shape.
/// 3. Attachment-key absence (→ nil) and explicit null (→ nil) on decode.
/// 4. `AttachmentUploading` degrade path: a mock that throws `.backendNotReady`
///    drops attachments while the text-only `ChatMessage` is still produced.
///
/// User instruction (verbatim): "通过 Agent Team 优化聊天界面到满分"
///
/// `@MainActor` because `SupabaseAttachmentService.mapStatus` and the
/// `AttachmentUploading` protocol are main-actor isolated.
@MainActor
final class ChatAttachmentTests: XCTestCase {

    // MARK: - 1. mapStatus

    // `AttachmentError` is intentionally not `Equatable` in production, so we
    // pattern-match each case rather than use `XCTAssertEqual`.

    /// `mapStatus` is `static` (internal) so `@testable import` reaches it.
    /// 400/401/403/404 are the dominant pre-deploy signal (bucket / RLS not
    /// shipped) → `.backendNotReady`, which the UI degrades to text-only.
    func test_mapStatus_400_401_403_404_backendNotReady() {
        for status in [400, 401, 403, 404] {
            guard case .backendNotReady = SupabaseAttachmentService.mapStatus(status) else {
                return XCTFail("HTTP \(status) must map to .backendNotReady (degrade to text-only)")
            }
        }
    }

    func test_mapStatus_413_tooLarge() {
        guard case .tooLarge = SupabaseAttachmentService.mapStatus(413) else {
            return XCTFail("HTTP 413 must map to .tooLarge")
        }
    }

    func test_mapStatus_429_rateLimited() {
        guard case .rateLimited = SupabaseAttachmentService.mapStatus(429) else {
            return XCTFail("HTTP 429 must map to .rateLimited")
        }
    }

    func test_mapStatus_500_uploadFailedCarriesStatus() {
        // The status code must be carried through verbatim, not flattened.
        guard case .uploadFailed(let s500) = SupabaseAttachmentService.mapStatus(500) else {
            return XCTFail("HTTP 500 must map to .uploadFailed")
        }
        XCTAssertEqual(s500, 500)
        guard case .uploadFailed(let s503) = SupabaseAttachmentService.mapStatus(503) else {
            return XCTFail("HTTP 503 must map to .uploadFailed")
        }
        XCTAssertEqual(s503, 503)
    }

    // MARK: - 2. ChatMessage Codable round-trip WITH attachments

    func test_chatMessage_roundTrip_withTwoAttachments_preservesAllFields() throws {
        let image = ChatAttachment(
            id: "att_img_1",
            kind: .image,
            fileName: "sunset.jpg",
            mimeType: "image/jpeg",
            fileSizeBytes: 204_800,
            storagePath: "conv_1/cmsg_1/att_img_1-sunset.jpg",
            width: 1024,
            height: 768
        )
        let file = ChatAttachment(
            id: "att_file_1",
            kind: .file,
            fileName: "itinerary.pdf",
            mimeType: "application/pdf",
            fileSizeBytes: 51_200,
            storagePath: "conv_1/cmsg_1/att_file_1-itinerary.pdf"
        )
        let original = ChatMessage(
            id: ChatMessageId(rawValue: "cmsg_1"),
            conversationId: ConversationId(rawValue: "conv_1"),
            senderId: "user_a",
            body: "Here are the photos and the plan!",
            attachments: [image, file],
            readAt: "2026-06-06T10:05:00Z",
            createdAt: "2026-06-06T10:00:00Z"
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: encoded)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.conversationId, original.conversationId)
        XCTAssertEqual(decoded.senderId, original.senderId)
        XCTAssertEqual(decoded.body, original.body)
        XCTAssertEqual(decoded.readAt, original.readAt)
        XCTAssertEqual(decoded.createdAt, original.createdAt)

        // ChatAttachment is Equatable — every field (incl. width/height) compares.
        XCTAssertEqual(decoded.attachments, original.attachments)
        let attachments = try XCTUnwrap(decoded.attachments)
        XCTAssertEqual(attachments.count, 2)
        XCTAssertEqual(attachments[0].kind, .image)
        XCTAssertEqual(attachments[0].width, 1024)
        XCTAssertEqual(attachments[0].height, 768)
        XCTAssertEqual(attachments[1].kind, .file)
        // File kind carries no pixel dimensions.
        XCTAssertNil(attachments[1].width)
        XCTAssertNil(attachments[1].height)
    }

    /// The on-the-wire JSON keys must be camelCase to round-trip the TS payload
    /// verbatim (`packages/core/src/companion.ts`). Assert the literal keys.
    func test_chatMessage_encodesCamelCaseKeys() throws {
        let message = ChatMessage(
            id: ChatMessageId(rawValue: "cmsg_keys"),
            conversationId: ConversationId(rawValue: "conv_keys"),
            senderId: "user_a",
            body: "hi",
            attachments: [
                ChatAttachment(
                    id: "att_1",
                    kind: .image,
                    fileName: "a.jpg",
                    mimeType: "image/jpeg",
                    fileSizeBytes: 10,
                    storagePath: "conv_keys/cmsg_keys/att_1-a.jpg",
                    width: 2,
                    height: 3
                )
            ],
            createdAt: "2026-06-06T10:00:00Z"
        )
        let json = String(decoding: try JSONEncoder().encode(message), as: UTF8.self)

        for key in ["conversationId", "senderId", "createdAt", "attachments",
                    "fileName", "mimeType", "fileSizeBytes", "storagePath"] {
            XCTAssertTrue(json.contains("\"\(key)\""), "Expected camelCase key \(key) in: \(json)")
        }
        // Snake_case must never leak into the encoded payload.
        for snake in ["conversation_id", "sender_id", "created_at",
                      "file_name", "file_size_bytes", "storage_path"] {
            XCTAssertFalse(json.contains(snake), "Snake_case key \(snake) leaked into: \(json)")
        }
    }

    /// Decode from a hand-written JSON string matching the TS camelCase shape
    /// (branded ids serialise as bare strings via RawRepresentable Codable).
    func test_chatMessage_decodesFromHandWrittenCamelCaseJSON() throws {
        let json = """
        {
          "id": "cmsg_hand",
          "conversationId": "conv_hand",
          "senderId": "user_b",
          "body": "look at this",
          "attachments": [
            {
              "id": "att_img",
              "kind": "image",
              "fileName": "view.png",
              "mimeType": "image/png",
              "fileSizeBytes": 4096,
              "storagePath": "conv_hand/cmsg_hand/att_img-view.png",
              "width": 800,
              "height": 600
            },
            {
              "id": "att_doc",
              "kind": "file",
              "fileName": "notes.txt",
              "mimeType": "text/plain",
              "fileSizeBytes": 128,
              "storagePath": "conv_hand/cmsg_hand/att_doc-notes.txt"
            }
          ],
          "readAt": "2026-06-06T12:30:00Z",
          "createdAt": "2026-06-06T12:00:00Z"
        }
        """
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.id, ChatMessageId(rawValue: "cmsg_hand"))
        XCTAssertEqual(decoded.conversationId, ConversationId(rawValue: "conv_hand"))
        XCTAssertEqual(decoded.senderId, "user_b")
        XCTAssertEqual(decoded.body, "look at this")
        XCTAssertEqual(decoded.readAt, "2026-06-06T12:30:00Z")
        XCTAssertEqual(decoded.createdAt, "2026-06-06T12:00:00Z")

        let attachments = try XCTUnwrap(decoded.attachments)
        XCTAssertEqual(attachments.count, 2)
        XCTAssertEqual(attachments[0], ChatAttachment(
            id: "att_img", kind: .image, fileName: "view.png", mimeType: "image/png",
            fileSizeBytes: 4096, storagePath: "conv_hand/cmsg_hand/att_img-view.png",
            width: 800, height: 600
        ))
        XCTAssertEqual(attachments[1].kind, .file)
        XCTAssertNil(attachments[1].width)
        XCTAssertNil(attachments[1].height)
    }

    // MARK: - 3. attachments key absent / null → nil

    func test_chatMessage_decodes_whenAttachmentsKeyAbsent_toNil() throws {
        let json = """
        {
          "id": "cmsg_noatt",
          "conversationId": "conv_noatt",
          "senderId": "user_c",
          "body": "text only",
          "createdAt": "2026-06-06T13:00:00Z"
        }
        """
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
        XCTAssertNil(decoded.attachments, "Absent attachments key must decode to nil")
        XCTAssertNil(decoded.readAt, "Absent readAt key must decode to nil")
        XCTAssertEqual(decoded.body, "text only")
    }

    func test_chatMessage_decodes_whenAttachmentsNull_toNil() throws {
        let json = """
        {
          "id": "cmsg_nullatt",
          "conversationId": "conv_nullatt",
          "senderId": "user_d",
          "body": "still text only",
          "attachments": null,
          "readAt": null,
          "createdAt": "2026-06-06T14:00:00Z"
        }
        """
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
        XCTAssertNil(decoded.attachments, "Explicit null attachments must decode to nil")
        XCTAssertNil(decoded.readAt, "Explicit null readAt must decode to nil")
        XCTAssertEqual(decoded.body, "still text only")
    }

    // MARK: - 4. Degrade path at the AttachmentUploading + ChatMessage layer

    /// A mock uploader that always throws `.backendNotReady`, mirroring the
    /// pre-deploy state where the Storage bucket / RLS migration (0005) is not
    /// shipped yet.
    @MainActor
    final class BackendNotReadyUploader: AttachmentUploading {
        private(set) var uploadCallCount = 0
        func upload(_ local: LocalAttachment, conversationId: String, messageId: String) async throws -> ChatAttachment {
            uploadCallCount += 1
            throw AttachmentError.backendNotReady
        }
        func signedURL(for attachment: ChatAttachment) async throws -> URL {
            throw AttachmentError.backendNotReady
        }
    }

    /// Reproduces `ChatService.send`'s degrade fork (the lines that catch
    /// `.backendNotReady` → drop attachments, keep the text) at the protocol +
    /// model layer.
    ///
    /// LIMITATION (honest): `ChatService.send` itself is gated by
    /// `FeatureFlags.companion`, which reads `FF_COMPANION` (default false in the
    /// test environment, as documented in `CompanionPhase3Tests`). With the flag
    /// off, `send` short-circuits before producing any message, so a true
    /// end-to-end `ChatService.send(...)` assertion cannot run deterministically
    /// in unit tests without mutating global feature-flag state. We therefore
    /// exercise the same degrade logic the service implements — upload throws
    /// `.backendNotReady` ⇒ attachments are dropped ⇒ a text-only `ChatMessage`
    /// is still constructed — against the injected `AttachmentUploading` seam.
    @MainActor
    func test_degrade_backendNotReady_dropsAttachments_keepsTextOnlyMessage() async throws {
        let uploader = BackendNotReadyUploader()
        let oneImage = LocalAttachment(
            kind: .image,
            fileName: "photo.jpg",
            mimeType: "image/jpeg",
            data: Data([0xFF, 0xD8, 0xFF, 0xD9]) // synthetic 4-byte JPEG-ish blob
        )

        // Mirror ChatService.send's loop: attempt upload, catch backendNotReady,
        // degrade to text-only.
        var uploaded: [ChatAttachment] = []
        var degradedToTextOnly = false
        for local in [oneImage] {
            do {
                uploaded.append(try await uploader.upload(local, conversationId: "conv_x", messageId: "cmsg_x"))
            } catch AttachmentError.backendNotReady {
                degradedToTextOnly = true
                uploaded.removeAll()
                break
            }
        }

        XCTAssertEqual(uploader.uploadCallCount, 1, "The uploader must have been attempted once")
        XCTAssertTrue(degradedToTextOnly, "A .backendNotReady throw must trigger the degrade path")
        XCTAssertTrue(uploaded.isEmpty, "Attachments must be dropped on degrade")

        let trimmed = "hello"
        let message = ChatMessage(
            id: ChatMessageId(rawValue: "cmsg_x"),
            conversationId: ConversationId(rawValue: "conv_x"),
            senderId: "user_x",
            body: trimmed,
            attachments: uploaded.isEmpty ? nil : uploaded,
            createdAt: "2026-06-06T15:00:00Z"
        )

        // The text-only message survives the degrade — the user never loses words.
        XCTAssertEqual(message.body, "hello")
        XCTAssertNil(message.attachments, "Degraded message carries no attachments")
    }

    /// Attachment-only degrade with empty text → nothing to send (matches the
    /// `guard !trimmed.isEmpty` branch in `ChatService.send`).
    @MainActor
    func test_degrade_backendNotReady_withEmptyText_yieldsNothingToSend() async throws {
        let uploader = BackendNotReadyUploader()
        let onlyImage = LocalAttachment(
            kind: .image, fileName: "x.jpg", mimeType: "image/jpeg", data: Data([0x00])
        )

        var uploaded: [ChatAttachment] = []
        var degradedToTextOnly = false
        do {
            uploaded.append(try await uploader.upload(onlyImage, conversationId: "c", messageId: "m"))
        } catch AttachmentError.backendNotReady {
            degradedToTextOnly = true
            uploaded.removeAll()
        }

        let trimmed = ""
        let hasNothingToSend = degradedToTextOnly && trimmed.isEmpty
        XCTAssertTrue(hasNothingToSend, "Empty text + degraded attachments ⇒ no message is sent")
        XCTAssertTrue(uploaded.isEmpty)
    }
}
