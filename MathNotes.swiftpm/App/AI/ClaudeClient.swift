import Foundation

/// A handwritten line transcribed by Claude.
struct RecognizedLine: Decodable {
    let kind: String
    let latex: String
    let expression: String
}

enum ClaudeError: LocalizedError {
    case http(status: Int, message: String)
    case refused
    case truncated
    case badResponse

    var errorDescription: String? {
        switch self {
        case .http(401, _): "Clé API refusée. Vérifie-la dans les Réglages."
        case .http(429, _): "Trop de requêtes pour le moment, réessaie dans un instant."
        case .http(529, _), .http(500..., _): "Claude est surchargé, réessaie dans un instant."
        case .http(let status, let message): "Erreur \(status) : \(message)"
        case .refused: "Claude a refusé de transcrire ces lignes."
        case .truncated: "Réponse incomplète de Claude."
        case .badResponse: "Réponse inattendue de Claude."
        }
    }
}

/// Calls the Claude Messages API over HTTPS (there is no official Swift SDK).
struct ClaudeClient {
    static let model = "claude-opus-5"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    let apiKey: String

    /// Transcribes handwritten lines (one PNG per line) into LaTeX and plain calculator syntax.
    func recognize(lineImages: [Data]) async throws -> [RecognizedLine] {
        var content: [[String: Any]] = []
        for (index, png) in lineImages.enumerated() {
            content.append(["type": "text", "text": "Line \(index + 1):"])
            content.append([
                "type": "image",
                "source": ["type": "base64", "media_type": "image/png", "data": png.base64EncodedString()],
            ])
        }
        content.append(["type": "text", "text": "Transcribe these \(lineImages.count) lines."])

        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 8000,
            // On a safety decline, the API retries with Anthropic's recommended fallback model.
            "fallbacks": "default",
            "system": Self.recognitionPrompt,
            "output_config": [
                "effort": "low",
                "format": ["type": "json_schema", "schema": Self.linesSchema],
            ],
            "messages": [["role": "user", "content": content]],
        ]

        struct Output: Decodable {
            let lines: [RecognizedLine]
        }
        let output = try JSONDecoder().decode(Output.self, from: try await send(body))
        guard output.lines.count == lineImages.count else { throw ClaudeError.badResponse }
        return output.lines
    }

    /// Sends a request and returns the JSON text of the structured output.
    private func send(_ body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            struct APIError: Decodable {
                struct Detail: Decodable { let message: String }
                let error: Detail
            }
            let message = (try? JSONDecoder().decode(APIError.self, from: data))?.error.message
            throw ClaudeError.http(status: status, message: message ?? String(decoding: data, as: UTF8.self))
        }

        struct Message: Decodable {
            struct Block: Decodable {
                let type: String
                let text: String?
            }
            let content: [Block]
            let stop_reason: String?
        }
        let message = try JSONDecoder().decode(Message.self, from: data)
        switch message.stop_reason {
        case "refusal": throw ClaudeError.refused
        case "max_tokens": throw ClaudeError.truncated
        default: break
        }
        let text = message.content.filter { $0.type == "text" }.compactMap(\.text).joined()
        guard let json = text.data(using: .utf8), !json.isEmpty else { throw ClaudeError.badResponse }
        return json
    }

    private static let recognitionPrompt = """
    You transcribe a student's handwritten math notes (usually in French), one line per image. \
    The app checks each calculation step against the previous one, so transcribe exactly what is written: \
    never fix mistakes, never simplify, never complete a line.

    For each image, in order, return:
    - kind: "math" for mathematics (expression, equation, calculation step), "text" for words, sentences or titles.
    - latex: the LaTeX transcription of the line, without $ delimiters. For a text line, the text itself.
    - expression: for a math line, the same content in plain calculator syntax: numbers with a dot as decimal \
    separator, variables (x, y, a, theta, x_1...), + - * / ^, parentheses, an explicit * for every multiplication, \
    the functions sqrt() cbrt() sin() cos() tan() arcsin() arccos() arctan() ln() log() exp() abs() with parentheses, \
    the constants pi and e, and = between the sides of an equation. If the line starts with "=", keep that leading "=". \
    Use an empty string for text lines and for anything this syntax can't express (inequalities, integrals, limits, \
    sums, sets, vectors...).

    Return exactly one entry per image, in the same order.
    """

    private static let linesSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "lines": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "kind": ["type": "string", "enum": ["math", "text"]],
                        "latex": ["type": "string"],
                        "expression": ["type": "string"],
                    ],
                    "required": ["kind", "latex", "expression"],
                    "additionalProperties": false,
                ],
            ],
        ],
        "required": ["lines"],
        "additionalProperties": false,
    ]
}
