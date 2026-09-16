#if canImport(JavaScriptCore)
import Foundation
import JavaScriptCore
import OpenComputerUseJavaScriptShim

/// A persistent JavaScriptCore runtime that exposes the Computer Use tools as a
/// synchronous `cua` API, so a model composes a multi-step flow (snapshot, find,
/// act, verify, loop, retry) in one `js` tool call instead of one tool call per
/// action. See docs/references/js-code-tool.md for the rationale.
///
/// The API is synchronous on purpose: every action runs in-process, so no
/// promises or top-level await are needed. Each `js` call runs in its own
/// function scope (via `new Function`), so `let`/`const` never collide across
/// calls; assign to `globalThis` for values that must survive to the next call.
/// Output is produced with `write(...)`; images with `emitImage(base64)`.
final class JavaScriptToolRuntime {
    typealias ToolCaller = (String, [String: Any]) throws -> ToolCallResult

    private let toolCaller: ToolCaller
    private var context: JSContext
    private var output = ""
    private var images: [Data] = []

    init(toolCaller: @escaping ToolCaller) {
        self.toolCaller = toolCaller
        self.context = JSContext()
        configure(context)
    }

    func reset() {
        let fresh = JSContext()!
        configure(fresh)
        context = fresh
    }

    func run(code: String, timeoutMs: Int) -> ToolCallResult {
        output = ""
        images = []

        let contextRef = UnsafeMutableRawPointer(context.jsGlobalContextRef)
        ocu_js_set_time_limit(contextRef, Double(max(1, timeoutMs)) / 1000.0)
        defer { ocu_js_clear_time_limit(contextRef) }

        context.exception = nil
        let runner = context.objectForKeyedSubscript("__ocuRun")
        let value = runner?.call(withArguments: [code])

        if let exception = context.exception {
            let message = exception.toString() ?? "JavaScript error"
            var text = output
            if !text.isEmpty { text += "\n" }
            text += "Error: " + message
            var content: [ToolResultContentItem] = [.text(text)]
            content.append(contentsOf: images.map { .pngImage($0) })
            return ToolCallResult(content: content, isError: true)
        }

        var text = output
        if let value, !value.isUndefined, !value.isNull {
            let repr = value.toString() ?? ""
            if !repr.isEmpty, repr != "undefined" {
                if !text.isEmpty { text += "\n" }
                text += repr
            }
        }

        var content: [ToolResultContentItem] = []
        if !text.isEmpty { content.append(.text(text)) }
        content.append(contentsOf: images.map { .pngImage($0) })
        if content.isEmpty { content.append(.text("(no output)")) }
        return ToolCallResult(content: content, isError: false)
    }

    private func configure(_ ctx: JSContext) {
        ctx.exceptionHandler = { context, exception in
            context?.exception = exception
        }

        let callBlock: @convention(block) (String, String) -> String = { [unowned self] tool, argsJSON in
            self.nativeCall(tool: tool, argsJSON: argsJSON)
        }
        ctx.setObject(callBlock, forKeyedSubscript: "__ocuCall" as NSString)

        let writeBlock: @convention(block) (String) -> Void = { [unowned self] text in
            self.output += text
        }
        ctx.setObject(writeBlock, forKeyedSubscript: "__ocuWrite" as NSString)

        let imageBlock: @convention(block) (String) -> Bool = { [unowned self] base64 in
            guard let data = Data(base64Encoded: base64) else { return false }
            self.images.append(data)
            return true
        }
        ctx.setObject(imageBlock, forKeyedSubscript: "__ocuEmitImage" as NSString)

        ctx.evaluateScript(Self.banner)
    }

    private func nativeCall(tool: String, argsJSON: String) -> String {
        if tool == "js" || tool == "js_reset" {
            return Self.errorJSON("tool '\(tool)' cannot be called from inside js")
        }

        let arguments: [String: Any]
        if argsJSON.isEmpty {
            arguments = [:]
        } else if let data = argsJSON.data(using: .utf8),
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            arguments = object
        } else {
            return Self.errorJSON("args for '\(tool)' must be a JSON object")
        }

        let result: ToolCallResult
        do {
            result = try toolCaller(tool, arguments)
        } catch let error as ComputerUseError {
            return Self.errorJSON(error.errorDescription ?? String(describing: error))
        } catch {
            return Self.errorJSON(String(describing: error))
        }

        var text = ""
        var encodedImages: [String] = []
        for item in result.content {
            let type = item.dictionary["type"] as? String
            if type == "text", let value = item.dictionary["text"] as? String {
                if !text.isEmpty { text += "\n" }
                text += value
            } else if type == "image", let value = item.dictionary["data"] as? String {
                encodedImages.append(value)
            }
        }

        let payload: [String: Any] = ["isError": result.isError, "text": text, "images": encodedImages]
        return Self.jsonString(payload)
    }

    private static func errorJSON(_ message: String) -> String {
        jsonString(["isError": true, "text": message, "images": [String]()])
    }

    private static func jsonString(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
            let text = String(data: data, encoding: .utf8) else {
            return "{\"isError\":true,\"text\":\"failed to encode result\",\"images\":[]}"
        }
        return text
    }

    private static let banner = """
    globalThis.cua = {
      call: function (tool, args) {
        var raw = __ocuCall(tool, JSON.stringify(args || {}));
        var res = JSON.parse(raw);
        if (res.isError) { throw new Error(res.text || ('tool error: ' + tool)); }
        return res;
      },
      listApps: function () { return this.call('list_apps', {}).text; },
      getAppState: function (app, opts) { return this.call('get_app_state', Object.assign({ app: app }, opts || {})).text; },
      click: function (app, opts) { return this.call('click', Object.assign({ app: app }, opts || {})).text; },
      type: function (app, text, opts) { return this.call('type_text', Object.assign({ app: app, text: text }, opts || {})).text; },
      pressKey: function (app, key, opts) { return this.call('press_key', Object.assign({ app: app, key: key }, opts || {})).text; },
      scroll: function (app, direction, element_index, pages) { return this.call('scroll', { app: app, direction: direction, element_index: element_index, pages: (pages == null ? 1 : pages) }).text; },
      drag: function (app, fromX, fromY, toX, toY) { return this.call('drag', { app: app, from_x: fromX, from_y: fromY, to_x: toX, to_y: toY }).text; },
      setValue: function (app, element_index, value) { return this.call('set_value', { app: app, element_index: element_index, value: value }).text; },
      secondaryAction: function (app, element_index, action) { return this.call('perform_secondary_action', { app: app, element_index: element_index, action: action }).text; },
      screenshot: function (app, opts) { var r = this.call('get_app_state', Object.assign({ app: app }, opts || {})); if (r.images && r.images.length) { __ocuEmitImage(r.images[0]); } return r.text; }
    };
    globalThis.write = function (value) { __ocuWrite(typeof value === 'string' ? value : JSON.stringify(value, null, 2)); };
    globalThis.emitImage = function (base64) { return __ocuEmitImage(String(base64)); };
    globalThis.console = {
      log: function () { __ocuWrite(Array.prototype.slice.call(arguments).map(function (x) { return typeof x === 'string' ? x : JSON.stringify(x); }).join(' ') + '\\n'); }
    };
    globalThis.console.error = globalThis.console.log;
    globalThis.console.warn = globalThis.console.log;
    globalThis.__ocuRun = function (src) { return (new Function(src))(); };
    """
}
#endif
