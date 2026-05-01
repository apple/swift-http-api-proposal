import JavaScriptKit

// https://developer.mozilla.org/en-US/docs/Web/API/Window/prompt
@JSFunction(from: .global) public func prompt(_ prompt: String, _ defaultValue: String) throws(JSException) -> String

// Prints to console and as div in HTML body
func div(_ line: String) {
    print(line);
    let document = JSObject.global.document
    let div = document.createElement("div")
    div.innerText = .string(line)
    _ = document.body.appendChild(div)
}

// Prints to console and as header in HTML body
func h2(_ line: String) {
    print(line);
    let document = JSObject.global.document
    let h2 = document.createElement("h2")
    h2.innerText = .string(line)
    _ = document.body.appendChild(h2)
}

// Creates a div status line that can be changed repeatedly.
// TODO: This is a hack. Find a way to remove @unchecked.
struct Status: @unchecked Sendable {
    let statusDiv: JSValue
    init() {
        let document = JSObject.global.document
        statusDiv = document.createElement("div")
        _ = document.body.appendChild(statusDiv)
    }

    func set(_ status: String) {
        print(status);
        statusDiv.innerText = .string(status)
    }
}
