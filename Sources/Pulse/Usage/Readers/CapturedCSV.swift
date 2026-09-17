import Foundation

/// A small RFC 4180 reader for the CSV exports some agents still write.
///
/// The legacy Cursor cache is the reason this exists: its rows embed model
/// names and money, a field can be wrapped in double quotes, and a quoted value
/// can hold a comma — so splitting on `,` puts the columns in the wrong places
/// and reads a model name as a token count. This walks the text once with a
/// quote state instead.
///
/// It is deliberately a **record reader, not a schema**: it returns rows of
/// fields and nothing else. Interpreting a header, coercing a number or
/// deciding what a blank means belongs to the caller, so a malformed row can be
/// skipped without this having guessed.
enum CapturedCSV {
    /// Every record in `text`, each a list of fields.
    ///
    /// Handles:
    /// - a field wrapped in `"…"`, with `""` inside it as one literal quote;
    /// - a comma inside a quoted field, kept as part of that field;
    /// - `\r\n`, `\n` and a lone `\r` all ending a record;
    /// - a final record with no trailing newline;
    /// - a leading UTF-8 byte-order mark, stripped rather than read as part of
    ///   the first header name.
    ///
    /// Newlines *inside* a quoted field are kept in the field, which is what
    /// RFC 4180 asks for. Nothing is repaired: an unterminated quote is simply
    /// the last field to the end of the file.
    static func rows(in text: String) -> [[String]] {
        var characters = Array(text.unicodeScalars)
        if characters.first?.value == 0xFEFF { characters.removeFirst() }

        var rows: [[String]] = []
        var record: [String] = []
        var field = String.UnicodeScalarView()
        var inQuotes = false

        func endField() {
            record.append(String(field))
            field = String.UnicodeScalarView()
        }

        func endRecord() {
            endField()
            rows.append(record)
            record = []
        }

        var index = 0
        while index < characters.count {
            let character = characters[index]
            if inQuotes {
                if character == "\"" {
                    // A doubled quote is one literal quote; a lone one closes.
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 2
                    } else {
                        inQuotes = false
                        index += 1
                    }
                } else {
                    field.append(character)
                    index += 1
                }
                continue
            }

            switch character {
            case "\"":
                inQuotes = true
                index += 1
            case ",":
                endField()
                index += 1
            case "\r":
                if index + 1 < characters.count, characters[index + 1] == "\n" { index += 2 } else { index += 1 }
                endRecord()
            case "\n":
                index += 1
                endRecord()
            default:
                field.append(character)
                index += 1
            }
        }

        // A record is only pending if something was written for it. A file that
        // ends on a newline must not grow a phantom empty record.
        if !field.isEmpty || !record.isEmpty { endRecord() }
        return rows
    }
}
