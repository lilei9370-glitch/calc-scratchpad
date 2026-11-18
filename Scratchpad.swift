import AppKit
import JavaScriptCore

@MainActor
enum Arithmetic {
    static let evaluate: JSValue = {
        let context = JSContext()!
        let url = Bundle.main.url(forResource: "math", withExtension: "js")!
        let source = try! String(contentsOf: url, encoding: .utf8)
        context.evaluateScript(source, withSourceURL: url)
        context.evaluateScript("""
            math.config({ number: "BigNumber", precision: 32 });
            function evaluateFormula(input) {
                try {
                    const result = math.evaluate(input);
                    return math.isBigNumber(result) ? result.toString() : null;
                } catch (error) {
                    return null;
                }
            }
            """)
        return context.objectForKeyedSubscript("evaluateFormula")
    }()

    static func result(for expression: String) -> String? {
        guard !expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let normalized = expression
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: #"(?<=[\d)])\s*[xX×]\s*(?=[\d(])"#, with: "*", options: .regularExpression)
            .replacingOccurrences(of: "÷", with: "/")
        if normalized.utf8.count <= 256 {
            let bytes = Array(normalized.utf8)
            if bytes.allSatisfy({ (48...57).contains($0) || [9, 32, 40, 41, 42, 43, 45, 46, 47].contains($0) }) {
                if !bytes.contains(where: { (48...57).contains($0) }) { return nil }
                let tail = bytes.last { $0 != 9 && $0 != 32 }
                if let tail, [40, 42, 43, 45, 47].contains(tail) { return nil }
                if bytes.filter({ $0 == 40 }).count > bytes.filter({ $0 == 41 }).count { return nil }
                var parser = DecimalArithmetic(bytes: bytes)
                if let result = parser.evaluate() { return result }
            }
        }
        let extended = normalized
            .replacingOccurrences(of: #"(\d+(?:\.\d*)?%)(?!\s*\d)"#, with: "($1)", options: .regularExpression)
        let value = evaluate.call(withArguments: [extended])
        return value?.isString == true ? value?.toString() : nil
    }

    static func display(_ result: String) -> String {
        guard !result.contains("e"), let integer = result.range(of: #"^-?\d+"#, options: .regularExpression) else {
            return result
        }
        let grouped = result[integer].replacingOccurrences(of: #"(?<=\d)(?=(\d{3})+$)"#,
                                                           with: ",", options: .regularExpression)
        return result.replacingCharacters(in: integer, with: grouped)
    }
}

private struct DecimalArithmetic {
    let bytes: [UInt8]
    private var position = 0
    private static let smallestPlain = Decimal(sign: .plus, exponent: -6, significand: 1)

    init(bytes: [UInt8]) { self.bytes = bytes }

    mutating func evaluate() -> String? {
        guard let value = expression(), nextByte() == nil,
              value == 0 || value.magnitude >= Self.smallestPlain else { return nil }
        return NSDecimalNumber(decimal: value).stringValue
    }

    private mutating func nextByte() -> UInt8? {
        while position < bytes.count, bytes[position] == 32 || bytes[position] == 9 { position += 1 }
        return position < bytes.count ? bytes[position] : nil
    }

    private mutating func expression(minimumPrecedence: Int = 1) -> Decimal? {
        guard var left = operand() else { return nil }
        while let op = nextByte() {
            let precedence: Int
            switch op {
            case 43, 45: precedence = 1 // + -
            case 42, 47: precedence = 2 // * /
            default: return left
            }
            if precedence < minimumPrecedence { return left }
            position += 1
            guard var right = expression(minimumPrecedence: precedence + 1) else { return nil }
            var result = Decimal()
            let status: Decimal.CalculationError
            switch op {
            case 43: status = NSDecimalAdd(&result, &left, &right, .plain)
            case 45: status = NSDecimalSubtract(&result, &left, &right, .plain)
            case 42: status = NSDecimalMultiply(&result, &left, &right, .plain)
            default: status = NSDecimalDivide(&result, &left, &right, .plain)
            }
            // Keep exact, compact values well within the original engine's 32-digit precision.
            guard status == .noError, result.exponent >= -12,
                  result.magnitude < 1_000_000_000_000_000 else { return nil }
            if op == 47 {
                var original = Decimal()
                guard NSDecimalMultiply(&original, &result, &right, .plain) == .noError,
                      original == left else { return nil }
            }
            left = result
        }
        return left
    }

    private mutating func operand() -> Decimal? {
        guard let first = nextByte() else { return nil }
        switch first {
        case 43, 45: // unary + or -
            position += 1
            return operand().map { first == 45 ? -$0 : $0 }
        case 40: // (
            position += 1
            guard let value = expression(), nextByte() == 41 else { return nil }
            position += 1
            return value
        default:
            let start = position
            while position < bytes.count, (48...57).contains(bytes[position]) { position += 1 }
            if position < bytes.count, bytes[position] == 46 {
                position += 1
                while position < bytes.count, (48...57).contains(bytes[position]) { position += 1 }
            }
            let length = position - start
            guard length > 0, length <= 15, length != 1 || first != 46 else { return nil }
            let literal = String(decoding: bytes[start..<position], as: UTF8.self)
            return Decimal(string: literal, locale: Locale(identifier: "en_US_POSIX"))
        }
    }
}

struct Line: Codable, Identifiable {
    var id = UUID()
    var formula = ""

    var blank: Bool { formula.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

struct Paper: Codable, Identifiable {
    var id = UUID()
    var lines = [Line()]
    var locked = false
    var editedAt: Date?

    var blank: Bool { lines.allSatisfy(\.blank) }
    var preview: String { lines.first(where: { !$0.blank })?.formula ?? "空白稿纸" }
}

struct Notebook: Codable {
    var papers = [Paper()]
    var selected = 0

    mutating func applyRetention(now: Date, legacyEditedAt: Date? = nil) -> Bool {
        var changed = false
        if let legacyEditedAt {
            for index in papers.indices where papers[index].editedAt == nil && !papers[index].blank {
                papers[index].editedAt = legacyEditedAt
                changed = true
            }
        }

        let current = papers[selected].id
        let cutoff = now.addingTimeInterval(-7 * 24 * 60 * 60)
        let kept = papers.filter { paper in
            if paper.blank { return paper.id == current }
            return paper.editedAt.map { $0 > cutoff } ?? true
        }
        if kept.count != papers.count {
            papers = kept
            if let index = papers.firstIndex(where: { $0.id == current }) {
                selected = index
            } else {
                papers.insert(Paper(), at: 0)
                selected = 0
            }
            changed = true
        }
        if papers[selected].blank, papers[selected].lines.count > 1, let last = papers[selected].lines.last {
            papers[selected].lines = [last]
            changed = true
        }
        return changed
    }
}

@MainActor
final class Scratchpad {
    private(set) var book = Notebook()
    private let url: URL
    var notice = ""
    var activeLine: UUID?

    var paper: Paper { book.papers[book.selected] }

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        url = support.appending(path: "计算便笺/稿纸.json")
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let saved = try JSONDecoder().decode(Notebook.self, from: Data(contentsOf: url))
                if saved.papers.indices.contains(saved.selected), saved.papers.allSatisfy({ !$0.lines.isEmpty }) {
                    book = saved
                    let now = Date()
                    let lastSaved = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    if book.applyRetention(now: now, legacyEditedAt: lastSaved ?? now) { save() }
                } else {
                    notice = "稿纸格式有误"
                }
            } catch {
                notice = "无法读取已保存的稿纸"
            }
        }
        activeLine = paper.locked ? nil : paper.lines.last?.id
    }

    func removeExpired() -> Bool {
        let current = paper.id
        guard book.applyRetention(now: Date()) else { return false }
        if paper.id != current || (activeLine != nil && !paper.lines.contains(where: { $0.id == activeLine })) {
            requestFocus(paper.locked ? nil : paper.lines.first?.id)
        }
        save()
        return true
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(book).write(to: url, options: .atomic)
            notice = ""
        } catch {
            notice = "保存失败"
        }
    }

    func requestFocus(_ id: UUID?) {
        activeLine = id
    }

    func select(_ index: Int) {
        book.selected = index
        requestFocus(paper.locked ? nil : paper.lines.first?.id)
        save()
    }

    func newPaper() {
        if book.papers.first?.blank == true { book.papers.removeFirst() }
        book.papers.insert(Paper(), at: 0)
        select(0)
    }

    func clear() {
        guard !paper.locked, !paper.blank else { return }
        book.papers[book.selected].lines = [Line()]
        book.papers[book.selected].editedAt = nil
        requestFocus(paper.lines[0].id)
        save()
    }

    func remove(all: Bool) {
        if all { book.papers.removeAll() }
        else { book.papers.remove(at: book.selected) }
        if book.papers.isEmpty { book.papers = [Paper()] }
        select(min(book.selected, book.papers.count - 1))
    }

    func toggleLock() {
        guard !paper.blank else { return }
        book.papers[book.selected].locked.toggle()
        requestFocus(paper.locked ? nil : paper.lines.last?.id)
        save()
    }

    func edit(_ id: UUID, formula: String) {
        guard !paper.locked, let index = paper.lines.firstIndex(where: { $0.id == id }),
              formula != paper.lines[index].formula else { return }
        book.papers[book.selected].lines[index].formula = formula
        book.papers[book.selected].editedAt = Date()
        if paper.blank {
            book.papers[book.selected].lines = [paper.lines[index]]
        } else if index == paper.lines.count - 1 && !paper.lines[index].blank {
            book.papers[book.selected].lines.append(Line())
        }
        save()
    }

    func finishEditing(_ id: UUID) {
        guard !paper.locked, let index = paper.lines.firstIndex(where: { $0.id == id }),
              index < paper.lines.count - 1, paper.lines[index].blank else { return }
        book.papers[book.selected].lines.remove(at: index)
        save()
    }

    func move(from id: UUID, by offset: Int, carry: String? = nil) {
        guard let index = paper.lines.firstIndex(where: { $0.id == id }),
              paper.lines.indices.contains(index + offset) else { return }
        let next = paper.lines[index + offset]
        if let carry, next.formula.isEmpty, paper.lines[index].formula != carry {
            edit(next.id, formula: carry)
        }
        requestFocus(next.id)
    }

    func pasteNumbers(average: Bool) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        let numbers = text.split(whereSeparator: \.isWhitespace)
        guard !numbers.isEmpty, numbers.allSatisfy({
            $0.range(of: #"^[+-]?((\d+|\d{1,3}(,\d{3})+)(\.\d*)?|\.\d+)$"#, options: .regularExpression) != nil
        }) else {
            notice = "请先复制一列数字"
            return
        }
        if paper.locked { newPaper() }
        let sum = numbers.joined(separator: "+").replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "+-", with: "-")
        let id = paper.lines.last!.id
        edit(id, formula: average ? "(\(sum))/\(numbers.count)" : sum)
        requestFocus(id)
    }

    func copy(_ result: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
        notice = "已复制结果"
    }

    func copyPaperImage() {
        let text = NSMutableAttributedString()
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 14
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: 576)]
        for line in paper.lines where !line.blank {
            if text.length > 0 { text.append(NSAttributedString(string: "\n")) }
            let result = Arithmetic.result(for: line.formula).map(Arithmetic.display) ?? ""
            text.append(NSAttributedString(string: "\(line.formula)\t\(result)", attributes: [
                .font: font, .foregroundColor: NSColor.black, .paragraphStyle: paragraph
            ]))
        }
        let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        let height = ceil(text.boundingRect(with: NSSize(width: 576, height: CGFloat.greatestFiniteMagnitude),
                                            options: options).height) + 44
        let image = NSImage(size: NSSize(width: 620, height: height), flipped: true) { bounds in
            NSColor.white.setFill()
            bounds.fill()
            text.draw(with: bounds.insetBy(dx: 22, dy: 22), options: options)
            return true
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        notice = "已复制稿纸图片"
    }
}

final class FormulaTextField: NSTextField {
    var copyResult: () -> Bool = { false }
}

class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class FormulaRow: FlippedView {
    let field = FormulaTextField()
    let result = NSButton(title: "", target: nil, action: nil)
    let line = NSBox()
    var focused = false
    var rawResult: String?
    private var formula: String?
    private var resultWidth: CGFloat = 112

    override init(frame: NSRect) {
        super.init(frame: frame)
        field.placeholderString = "输入算式"
        field.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.setAccessibilityLabel("算式")
        result.isBordered = false
        result.font = .monospacedSystemFont(ofSize: 16, weight: .semibold)
        result.alignment = .right
        result.lineBreakMode = .byTruncatingMiddle
        line.boxType = .custom
        line.borderWidth = 0
        line.fillColor = NSColor.separatorColor.withAlphaComponent(0.16)
        [field, result, line].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(_ item: Line, locked: Bool, focused: Bool) {
        if field.isEditable == locked { field.isEditable = !locked }
        if formula != item.formula {
            formula = item.formula
            if field.currentEditor() == nil, field.stringValue != item.formula { field.stringValue = item.formula }
            rawResult = Arithmetic.result(for: item.formula)
            let display = rawResult.map(Arithmetic.display) ?? ""
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .right
            paragraph.lineBreakMode = .byTruncatingMiddle
            result.attributedTitle = NSAttributedString(string: display, attributes: [
                .foregroundColor: NSColor.labelColor, .font: result.font!, .paragraphStyle: paragraph,
            ])
            result.isHidden = rawResult == nil
            result.toolTip = rawResult.map { "复制结果 \($0)" }
            result.setAccessibilityLabel("复制结果 \(display)")
            resultWidth = max(112, min(220, CGFloat(display.count) * 6 + 16))
            needsLayout = true
        }
        if self.focused != focused {
            self.focused = focused
            needsDisplay = true
        }
        line.isHidden = focused || item.blank
    }

    override func layout() {
        super.layout()
        field.frame = NSRect(x: 10, y: 5, width: max(0, bounds.width - resultWidth - 25), height: 24)
        result.frame = NSRect(x: bounds.width - resultWidth - 17, y: 5, width: resultWidth, height: 24)
        line.frame = NSRect(x: 10, y: 33.5, width: max(0, bounds.width - 20), height: 0.5)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard focused else { return }
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.4, dy: 0.4), xRadius: 6, yRadius: 6)
        NSColor.controlAccentColor.withAlphaComponent(0.055).setFill()
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.38).setStroke()
        path.lineWidth = 0.75
        path.stroke()
    }
}

@MainActor
final class PaperContent: FlippedView, NSTextFieldDelegate, NSPopoverDelegate {
    let model: Scratchpad
    private let scroll = NSScrollView()
    private let document = FlippedView()
    private let status = NSTextField(labelWithString: "")
    private let toolbar = FlippedView()
    private let rule = NSBox()
    private let history = NSPopover()
    private var rows: [UUID: FormulaRow] = [:]

    private lazy var historyButton = icon("clock", "历史稿纸", #selector(showHistory))
    private lazy var newButton = icon("plus", "新建稿纸（⌘N）", #selector(newPaper))
    private lazy var moreButton = icon("ellipsis", "更多操作", #selector(showMore))
    private lazy var lockIndicator = NSImageView(image: NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "已锁定")!)

    init(model: Scratchpad) {
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = document
        rule.boxType = .separator
        status.font = .systemFont(ofSize: 11)
        lockIndicator.contentTintColor = .secondaryLabelColor
        [toolbar, rule, scroll, status].forEach(addSubview)
        [historyButton, newButton, moreButton, lockIndicator].forEach(toolbar.addSubview)
        history.behavior = .transient
        history.delegate = self
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
    }

    override var wantsUpdateLayer: Bool { true }

    private func icon(_ symbol: String, _ title: String, _ selector: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)!
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))!
        let button = NSButton(image: image, target: self, action: selector)
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = title
        button.setAccessibilityLabel(title)
        return button
    }

    override func layout() {
        super.layout()
        toolbar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 40)
        historyButton.frame = NSRect(x: 14, y: 7, width: 27, height: 26)
        lockIndicator.frame = NSRect(x: 50, y: 13, width: 14, height: 14)
        newButton.frame = NSRect(x: bounds.width - 70, y: 7, width: 27, height: 26)
        moreButton.frame = NSRect(x: bounds.width - 38, y: 7, width: 27, height: 26)
        rule.frame = NSRect(x: 0, y: 40, width: bounds.width, height: 1)
        let footer: CGFloat = status.isHidden ? 0 : 30
        scroll.frame = NSRect(x: 0, y: 41, width: bounds.width, height: max(0, bounds.height - 41 - footer))
        status.frame = NSRect(x: 17, y: bounds.height - 23, width: bounds.width - 34, height: 15)
        let height = CGFloat(rows.count) * 35 + 22
        let width = scroll.contentSize.width
        document.frame.size = NSSize(width: width, height: max(height, scroll.contentSize.height))
        var y: CGFloat = 11
        for item in model.paper.lines {
            guard let row = rows[item.id] else { continue }
            row.frame = NSRect(x: 15, y: y, width: max(0, width - 30), height: 34)
            y += 35
        }
    }

    func refresh(focus: Bool = false) {
        let paper = model.paper
        let items = paper.locked ? paper.lines.filter { !$0.blank } : paper.lines
        let ids = Set(items.map(\.id))
        for id in Array(rows.keys) where !ids.contains(id) { rows.removeValue(forKey: id)?.removeFromSuperview() }
        for item in items {
            let row: FormulaRow
            if let existing = rows[item.id] {
                row = existing
            } else {
                row = FormulaRow()
                row.field.delegate = self
                row.field.copyResult = { [weak self, weak row] in
                    guard let self, let row, row.rawResult != nil else { return false }
                    self.copyResult(row.result)
                    return true
                }
                row.result.target = self
                row.result.action = #selector(copyResult(_:))
                rows[item.id] = row
                document.addSubview(row)
            }
            row.update(item, locked: paper.locked, focused: model.activeLine == item.id && !paper.locked)
        }
        status.stringValue = model.notice
        status.textColor = model.notice == "保存失败" ? .systemRed : .secondaryLabelColor
        status.isHidden = model.notice.isEmpty
        lockIndicator.isHidden = !paper.locked
        needsLayout = true
        if focus {
            layoutSubtreeIfNeeded()
            if let id = model.activeLine, let row = rows[id], let window {
                document.scrollToVisible(row.frame)
                window.makeFirstResponder(row.field)
                (window as? PaperWindow)?.activeField = row.field
                if let editor = row.field.currentEditor() {
                    editor.selectedRange = NSRange(location: (editor.string as NSString).length, length: 0)
                }
            } else {
                window?.makeFirstResponder(nil)
                scroll.contentView.scroll(to: .zero)
            }
        }
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        guard let field = notification.object as? FormulaTextField,
              let (id, _) = rows.first(where: { $0.value.field === field }) else { return }
        (window as? PaperWindow)?.activeField = field
        model.activeLine = id
        refresh()
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? FormulaTextField,
              let (id, _) = rows.first(where: { $0.value.field === field }) else { return }
        model.edit(id, formula: field.currentEditor()?.string ?? field.stringValue)
        refresh()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? FormulaTextField,
              let (id, _) = rows.first(where: { $0.value.field === field }) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, model.activeLine != id else { return }
            model.finishEditing(id)
            refresh()
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
        guard !textView.hasMarkedText(), let id = model.activeLine else { return false }
        switch command {
        case #selector(NSResponder.insertNewline(_:)):
            model.move(from: id, by: 1, carry: Arithmetic.result(for: textView.string))
        case #selector(NSResponder.moveUp(_:)): model.move(from: id, by: -1)
        case #selector(NSResponder.moveDown(_:)): model.move(from: id, by: 1)
        default: return false
        }
        refresh(focus: true)
        return true
    }

    @objc func newPaper() { model.newPaper(); refresh(focus: true) }
    @objc func clearPaper() { model.clear(); refresh(focus: true) }

    @objc private func copyResult(_ sender: NSButton) {
        guard let row = sender.superview as? FormulaRow, let result = row.rawResult else { return }
        model.copy(result)
        refresh()
    }

    @objc private func showHistory() {
        if history.isShown { history.close(); return }
        if model.removeExpired() { refresh(focus: true) }
        let entries = model.book.papers.enumerated()
            .filter { !$0.element.blank || $0.offset == model.book.selected }
            .sorted { ($0.element.editedAt ?? .distantFuture) > ($1.element.editedAt ?? .distantFuture) }
        let height = min(238, CGFloat(entries.count) * 33 + 9)
        let view = FlippedView(frame: NSRect(x: 0, y: 0, width: 292, height: height + 38))
        let hint = NSTextField(labelWithString: "从最后一次编辑起保留 7 天")
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 11)
        hint.frame = NSRect(x: 13, y: 12, width: 266, height: 16)
        view.addSubview(hint)
        let list = NSScrollView(frame: NSRect(x: 6, y: 34, width: 280, height: height))
        list.drawsBackground = false
        list.hasVerticalScroller = true
        list.autohidesScrollers = true
        let container = FlippedView(frame: NSRect(x: 0, y: 0, width: 280, height: CGFloat(entries.count) * 33 + 8))
        for (position, entry) in entries.enumerated() {
            let selected = entry.offset == model.book.selected
            let image = NSImage(systemSymbolName: selected ? "checkmark" : entry.element.locked ? "lock" : "doc.text",
                                accessibilityDescription: selected ? "当前稿纸" : nil)!
            let button = NSButton(title: entry.element.preview, image: image, target: self, action: #selector(selectPaper(_:)))
            button.isBordered = false
            button.alignment = .left
            button.imagePosition = .imageLeading
            button.font = entry.element.blank ? .systemFont(ofSize: 13) : .monospacedSystemFont(ofSize: 13, weight: .regular)
            button.lineBreakMode = .byTruncatingTail
            button.identifier = NSUserInterfaceItemIdentifier(entry.element.id.uuidString)
            button.frame = NSRect(x: 5, y: CGFloat(position) * 33 + 1, width: 264, height: 30)
            if selected {
                button.wantsLayer = true
                button.layer?.cornerRadius = 5
                button.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.09).cgColor
            }
            container.addSubview(button)
        }
        list.documentView = container
        view.addSubview(list)
        let controller = NSViewController()
        controller.view = view
        history.contentViewController = controller
        history.contentSize = view.frame.size
        history.show(relativeTo: historyButton.bounds, of: historyButton, preferredEdge: .maxY)
    }

    @objc private func selectPaper(_ button: NSButton) {
        history.close()
        guard let index = model.book.papers.firstIndex(where: { $0.id.uuidString == button.identifier?.rawValue }) else { return }
        model.select(index)
        refresh(focus: true)
    }

    func popoverDidClose(_ notification: Notification) {
        history.contentViewController = nil
    }

    @objc private func showMore() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        func add(_ title: String, _ action: Selector, enabled: Bool = true) {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
            item.isEnabled = enabled
        }
        add(model.paper.locked ? "解锁稿纸" : "锁定稿纸", #selector(toggleLock), enabled: !model.paper.blank)
        add("复制为图片", #selector(copyImage), enabled: !model.paper.blank)
        menu.addItem(.separator())
        add("粘贴数字求和", #selector(pasteSum))
        add("粘贴数字求平均", #selector(pasteAverage))
        menu.addItem(.separator())
        add("清空当前稿纸", #selector(clearPaper), enabled: !model.paper.locked && !model.paper.blank)
        add("删除当前稿纸", #selector(deletePaper))
        add("删除全部稿纸", #selector(deleteAll))
        menu.popUp(positioning: nil, at: NSPoint(x: moreButton.bounds.maxX, y: moreButton.bounds.minY), in: moreButton)
    }
    @objc private func toggleLock() { model.toggleLock(); refresh(focus: true) }
    @objc private func copyImage() { model.copyPaperImage(); refresh() }
    @objc private func pasteSum() { model.pasteNumbers(average: false); refresh(focus: true) }
    @objc private func pasteAverage() { model.pasteNumbers(average: true); refresh(focus: true) }
    @objc private func deletePaper() { confirmDeletion(all: false) }
    @objc private func deleteAll() { confirmDeletion(all: true) }

    private func confirmDeletion(all: Bool) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = all ? "删除全部稿纸" : "删除当前稿纸"
        alert.informativeText = "删除后无法恢复。"
        alert.addButton(withTitle: "删除").hasDestructiveAction = true
        alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { [weak self] result in
            guard result == .alertFirstButtonReturn, let self else { return }
            model.remove(all: all)
            refresh(focus: true)
        }
    }
}

final class PaperWindow: NSWindow {
    weak var activeField: FormulaTextField?

    func copyCurrentResult() -> Bool {
        guard let input = activeField, let editor = input.currentEditor() as? NSTextView,
              editor === firstResponder, editor.selectedRange().length == 0 else { return false }
        return input.copyResult()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command,
           let input = activeField, let editor = input.currentEditor() as? NSTextView, editor === firstResponder {
            if event.charactersIgnoringModifiers == "c", copyCurrentResult() { return true }
            if event.charactersIgnoringModifiers == "v",
               let text = NSPasteboard.general.string(forType: .string) {
                let grouping = try! NSRegularExpression(pattern: #"(?<![\d,])\d{1,3}(?:,\d{3})+(?![\d,])"#)
                var cleaned = text
                for match in grouping.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                    if let range = Range(match.range, in: cleaned) {
                        cleaned.replaceSubrange(range, with: cleaned[range].replacingOccurrences(of: ",", with: ""))
                    }
                }
                if cleaned != text {
                    editor.insertText(cleaned, replacementRange: editor.selectedRange())
                    return true
                }
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

@main
@MainActor
final class ScratchpadApp: NSObject, NSApplicationDelegate {
    let model = Scratchpad()
    var window: PaperWindow!
    private var content: PaperContent!
    private var expiryTimer: Timer?

    static func main() {
        if CommandLine.arguments.dropFirst().first == "--calculate" {
            for expression in CommandLine.arguments.dropFirst(2) {
                print(Arithmetic.result(for: expression) ?? "—")
            }
            return
        }
        let app = NSApplication.shared
        let delegate = ScratchpadApp()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu()
        let appMenu = NSMenuItem()
        appMenu.submenu = NSMenu()
        appMenu.submenu?.addItem(withTitle: "退出计算便笺", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(appMenu)

        let paperMenu = NSMenuItem()
        paperMenu.submenu = NSMenu(title: "稿纸")
        paperMenu.submenu?.addItem(withTitle: "新建稿纸", action: #selector(newPaper), keyEquivalent: "n").target = self
        paperMenu.submenu?.addItem(withTitle: "清空当前稿纸", action: #selector(clearFromMenu), keyEquivalent: "r").target = self
        paperMenu.submenu?.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        menu.addItem(paperMenu)

        let editMenu = NSMenuItem()
        editMenu.submenu = NSMenu(title: "编辑")
        editMenu.submenu?.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.submenu?.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.submenu?.addItem(withTitle: "复制", action: #selector(copyFromMenu(_:)), keyEquivalent: "c").target = self
        editMenu.submenu?.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.submenu?.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(editMenu)
        NSApp.mainMenu = menu

        window = PaperWindow(contentRect: NSRect(x: 0, y: 0, width: 530, height: 340),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
        window.title = "计算便笺"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 350, height: 230)
        content = PaperContent(model: model)
        window.contentView = content
        window.center()
        window.setFrameAutosaveName("Scratchpad")
        showPaper()
        content.refresh(focus: true)
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.expirePapers() }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        expirePapers()
    }

    private func expirePapers() {
        if model.removeExpired() { content?.refresh(focus: true) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPaper()
        return false
    }

    @objc func newPaper() { content.newPaper(); showPaper() }
    @objc func clearFromMenu() { content.clearPaper() }
    @objc func copyFromMenu(_ sender: Any?) {
        if window?.copyCurrentResult() != true {
            NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: sender)
        }
    }

    func showPaper() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func application(_ application: NSApplication, open urls: [URL]) {
        if urls.contains(where: { $0.scheme == "leizi-scratchpad" && $0.host == "quote" && $0.path.isEmpty }) {
            if model.paper.locked { model.newPaper() }
            let id = model.paper.lines.last!.id
            model.edit(id, formula: "1.25*")
            model.requestFocus(id)
        }
        if window != nil { showPaper(); content.refresh(focus: true) }
    }
}
