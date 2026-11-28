import SwiftUI
import UIKit

/// Custom UITextView that intercepts Backspace at position 0 (including empty blocks)
/// and auto-sizes cleanly to its wrapped content inside a SwiftUI ScrollView.
final class BlockUITextView: UITextView {
    var onBackspaceAtStart: (() -> Void)?

    private let placeholderLabel: UILabel = {
        let lbl = UILabel()
        lbl.numberOfLines = 0
        lbl.isUserInteractionEnabled = false
        return lbl
    }()

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        backgroundColor = .clear
        isScrollEnabled = false
        textContainerInset = .zero
        self.textContainer.lineFragmentPadding = 0
        self.textContainer.widthTracksTextView = true
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultHigh, for: .vertical)

        addSubview(placeholderLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var placeholder: String = "" {
        didSet {
            placeholderLabel.text = placeholder
            updatePlaceholderVisibility()
            setNeedsLayout()
        }
    }

    var placeholderColor: UIColor = .placeholderText {
        didSet { placeholderLabel.textColor = placeholderColor }
    }

    override var font: UIFont? {
        didSet {
            placeholderLabel.font = font
            setNeedsLayout()
        }
    }

    override var text: String! {
        didSet { updatePlaceholderVisibility() }
    }

    override var attributedText: NSAttributedString! {
        didSet { updatePlaceholderVisibility() }
    }

    func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !(text ?? "").isEmpty || placeholder.isEmpty
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = max(0, bounds.width)
        let size = placeholderLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        placeholderLabel.frame = CGRect(x: 0, y: 0, width: width, height: size.height)
    }

    override func deleteBackward() {
        if selectedRange.location == 0 && selectedRange.length == 0 {
            onBackspaceAtStart?()
            return
        }
        super.deleteBackward()
    }
}

struct BlockTextView: UIViewRepresentable {
    let text: String
    let placeholder: String
    let font: UIFont
    let textColor: UIColor
    let placeholderColor: UIColor
    let strikethrough: Bool
    let isCode: Bool
    let isFocused: Bool
    let shouldResign: Bool
    let requestedCursor: Int?

    let onTextChange: (String) -> Void
    let onReturn: (_ head: String, _ tail: String) -> Void
    let onBackspaceAtStart: () -> Void
    let onFocus: () -> Void
    let onCursorApplied: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> BlockUITextView {
        let tv = BlockUITextView()
        tv.delegate = context.coordinator
        tv.font = font
        tv.textColor = textColor
        tv.tintColor = textColor
        tv.placeholder = placeholder
        tv.placeholderColor = placeholderColor
        tv.autocapitalizationType = isCode ? .none : .sentences
        tv.autocorrectionType = isCode ? .no : .default
        tv.smartQuotesType = isCode ? .no : .default
        tv.smartDashesType = isCode ? .no : .default
        tv.returnKeyType = .default
        tv.onBackspaceAtStart = {
            context.coordinator.parent.onBackspaceAtStart()
        }
        applyStyledText(to: tv, text: text)
        if isFocused {
            DispatchQueue.main.async {
                if !tv.isFirstResponder {
                    tv.becomeFirstResponder()
                }
                if let pos = requestedCursor {
                    let len = (tv.text as NSString).length
                    tv.selectedRange = NSRange(location: min(max(0, pos), len), length: 0)
                    onCursorApplied()
                }
            }
        }
        return tv
    }

    func updateUIView(_ tv: BlockUITextView, context: Context) {
        context.coordinator.parent = self
        tv.onBackspaceAtStart = {
            context.coordinator.parent.onBackspaceAtStart()
        }

        tv.placeholder = placeholder
        tv.placeholderColor = placeholderColor
        tv.tintColor = textColor
        tv.autocapitalizationType = isCode ? .none : .sentences
        tv.autocorrectionType = isCode ? .no : .default
        tv.smartQuotesType = isCode ? .no : .default
        tv.smartDashesType = isCode ? .no : .default

        let needsTextSync = tv.text != text
        let needsStyleSync = context.coordinator.lastFont != font
            || context.coordinator.lastColor != textColor
            || context.coordinator.lastStrike != strikethrough

        if needsTextSync || needsStyleSync {
            let prevRange = tv.selectedRange
            context.coordinator.isUpdatingFromSwiftUI = true
            applyStyledText(to: tv, text: text)
            let len = (tv.text as NSString).length
            let clamped = min(prevRange.location, len)
            tv.selectedRange = NSRange(location: clamped, length: 0)
            context.coordinator.isUpdatingFromSwiftUI = false
            tv.invalidateIntrinsicContentSize()
        }

        context.coordinator.lastFont = font
        context.coordinator.lastColor = textColor
        context.coordinator.lastStrike = strikethrough
        tv.updatePlaceholderVisibility()

        if isFocused {
            if !tv.isFirstResponder {
                DispatchQueue.main.async {
                    if !tv.isFirstResponder {
                        tv.becomeFirstResponder()
                    }
                    if let pos = requestedCursor {
                        let len = (tv.text as NSString).length
                        tv.selectedRange = NSRange(location: min(max(0, pos), len), length: 0)
                        onCursorApplied()
                    }
                }
            } else if let pos = requestedCursor {
                DispatchQueue.main.async {
                    let len = (tv.text as NSString).length
                    tv.selectedRange = NSRange(location: min(max(0, pos), len), length: 0)
                    onCursorApplied()
                }
            }
        } else if shouldResign && tv.isFirstResponder {
            DispatchQueue.main.async {
                if tv.isFirstResponder {
                    tv.resignFirstResponder()
                }
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: BlockUITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width
        let target = CGSize(width: max(1, width), height: .greatestFiniteMagnitude)
        let fitted = uiView.sizeThatFits(target)
        let minLine = ceil(font.lineHeight)
        return CGSize(width: width, height: max(minLine, ceil(fitted.height)))
    }

    private func applyStyledText(to tv: BlockUITextView, text: String) {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
        ]
        if strikethrough {
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attrs[.strikethroughColor] = textColor
        }
        tv.typingAttributes = attrs
        tv.attributedText = NSAttributedString(string: text, attributes: attrs)
        tv.font = font
        tv.textColor = textColor
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: BlockTextView
        var isUpdatingFromSwiftUI = false
        var lastFont: UIFont?
        var lastColor: UIColor?
        var lastStrike: Bool = false

        init(_ parent: BlockTextView) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isFocused {
                parent.onFocus()
            }
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if !parent.isCode && text == "\n" {
                let current = (textView.text ?? "") as NSString
                let head = current.substring(to: min(range.location, current.length))
                let tailStart = min(range.location + range.length, current.length)
                let tail = current.substring(from: tailStart)
                parent.onReturn(head, tail)
                return false
            }
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdatingFromSwiftUI else { return }
            (textView as? BlockUITextView)?.updatePlaceholderVisibility()
            let newText = textView.text ?? ""
            parent.onTextChange(newText)
            textView.invalidateIntrinsicContentSize()
        }
    }
}

enum HebdoFonts {
    static func serif(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        if let desc = base.fontDescriptor.withDesign(.serif) {
            return UIFont(descriptor: desc, size: size)
        }
        return UIFont(name: "Georgia", size: size) ?? base
    }

    static func mono(size: CGFloat) -> UIFont {
        UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}
