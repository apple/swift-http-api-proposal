// https://developer.mozilla.org/en-US/docs/Web/API/URL
@JSClass(jsName: "URL", from: .global) struct JSURL {
    @JSFunction init(_ url: String) throws(JSException)
    @JSGetter var `protocol`: String
    @JSGetter var host: String
    @JSGetter var pathname: String
    @JSGetter var search: String
}
