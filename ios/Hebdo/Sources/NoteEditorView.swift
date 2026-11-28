import SwiftUI
import UIKit

struct NoteEditorView: View {
    @EnvironmentObject private var store: NoteStore
    @Environment(\.colorScheme) private var colorScheme

    let initialPath: String
    let draftTemplate: String?
    let allowTitleEdit: Bool

    @State private var currentPath: String
    @State private var titleText: String
    @State private var blocks: [NoteBlock] = []
    @State private var lastSavedMd: String = ""
    @State private var isDraft: Bool
    @State private var saveTask: Task<Void, Never>?
    @State private var focusedBlockID: UUID?
    @State private var pendingCursorBlockID: UUID?
    @State private var pendingCursorOffset: Int?

    init(initialPath: String, draftTemplate: String?, allowTitleEdit: Bool) {
        self.initialPath = initialPath
        self.draftTemplate = draftTemplate
        self.allowTitleEdit = allowTitleEdit
        _currentPath = State(initialValue: initialPath)
        let base = ((initialPath as NSString).lastPathComponent as NSString).deletingPathExtension
        _titleText = State(initialValue: base)
        _isDraft = State(initialValue: draftTemplate != nil)
    }

    private var breadcrumb: String {
        let dir = (currentPath as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir.replacingOccurrences(of: "/", with: " / ")
    }

    var body: some View {
        ScrollView {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 4) {
                    if !breadcrumb.isEmpty {
                        Text(breadcrumb)
                            .font(.system(size: 13, design: .serif))
                            .foregroundStyle(HebdoTheme.faint)
                            .padding(.bottom, 2)
                    }

                    if allowTitleEdit {
                        TextField("Untitled", text: $titleText)
                            .font(.system(size: 34, weight: .bold, design: .serif))
                            .foregroundStyle(HebdoTheme.text)
                            .padding(.bottom, 10)
                            .onSubmit { commitRename() }
                    } else {
                        Text(titleText)
                            .font(.system(size: 34, weight: .bold, design: .serif))
                            .foregroundStyle(HebdoTheme.text)
                            .padding(.bottom, 10)
                    }

                    ForEach(Array(blocks.enumerated()), id: \.element.id) { idx, _ in
                        blockRow(at: idx)
                    }

                    // Tap empty space below blocks to continue writing
                    Color.clear
                        .frame(height: 180)
                        .contentShape(Rectangle())
                        .onTapGesture { appendOrFocusLast() }
                }
                .padding(.horizontal, 22)
                .padding(.top, 16)
                .padding(.bottom, 40)
                .frame(maxWidth: 720, alignment: .leading)
                Spacer(minLength: 0)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(HebdoTheme.bg)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        typeButton(.todo, icon: "checkmark.square", label: "To-do")
                        typeButton(.h1, icon: "textformat.size.larger", label: "H1")
                        typeButton(.h2, icon: "textformat.size", label: "H2")
                        typeButton(.ul, icon: "list.bullet", label: "Bullet")
                        typeButton(.ol, icon: "list.number", label: "Numbered")
                        typeButton(.callout, icon: "lightbulb", label: "Callout")
                        typeButton(.quote, icon: "text.quote", label: "Quote")
                        typeButton(.code, icon: "chevron.left.forwardslash.chevron.right", label: "Code")
                        typeButton(.divider, icon: "minus", label: "Divider")
                    }
                    .foregroundStyle(HebdoTheme.text)
                }
                Spacer()
                Button("Done") { focusedBlockID = nil }
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .foregroundStyle(HebdoTheme.accent)
            }
        }
        .onAppear { loadNote() }
        .onDisappear { flushSave() }
    }

    // MARK: - Block Rendering

    private func blockEditor(
        at idx: Int,
        placeholder: String,
        font: UIFont,
        color: Color? = nil,
        strikethrough: Bool = false,
        isCode: Bool = false
    ) -> some View {
        let _ = colorScheme // ensure theme colors refresh on Light/Dark switch
        let block = blocks[idx]
        let blockID = block.id
        let resolvedColor = UIColor(color ?? HebdoTheme.text)
        let placeholderUIColor = UIColor(HebdoTheme.faint)

        return BlockTextView(
            text: block.text,
            placeholder: placeholder,
            font: font,
            textColor: resolvedColor,
            placeholderColor: placeholderUIColor,
            strikethrough: strikethrough,
            isCode: isCode,
            isFocused: focusedBlockID == blockID,
            shouldResign: focusedBlockID == nil,
            requestedCursor: pendingCursorBlockID == blockID ? pendingCursorOffset : nil,
            onTextChange: { newVal in
                guard let liveIdx = blocks.firstIndex(where: { $0.id == blockID }) else { return }
                handleTextChange(at: liveIdx, newVal: newVal)
            },
            onReturn: { head, tail in
                guard let liveIdx = blocks.firstIndex(where: { $0.id == blockID }) else { return }
                handleReturn(at: liveIdx, head: head, tail: tail)
            },
            onBackspaceAtStart: {
                guard let liveIdx = blocks.firstIndex(where: { $0.id == blockID }) else { return }
                handleBackspaceAtStart(at: liveIdx)
            },
            onFocus: {
                focusedBlockID = blockID
            },
            onCursorApplied: {
                if pendingCursorBlockID == blockID {
                    pendingCursorBlockID = nil
                    pendingCursorOffset = nil
                }
            }
        )
    }

    @ViewBuilder
    private func blockRow(at idx: Int) -> some View {
        let block = blocks[idx]

        switch block.type {
        case .divider:
            HStack {
                Rectangle()
                    .fill(HebdoTheme.border)
                    .frame(height: 1)
            }
            .padding(.vertical, 10)
            .contextMenu {
                Button("Delete divider", role: .destructive) { deleteBlock(at: idx) }
            }

        case .code:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    TextField("language", text: Binding(
                        get: { idx < blocks.count ? blocks[idx].lang : "" },
                        set: { if idx < blocks.count { blocks[idx].lang = $0; scheduleSave() } }
                    ))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(HebdoTheme.muted)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = block.text
                    } label: {
                        Text("Copy")
                            .font(.system(size: 12))
                            .foregroundStyle(HebdoTheme.faint)
                    }
                }
                blockEditor(
                    at: idx,
                    placeholder: "Code…",
                    font: HebdoFonts.mono(size: 14),
                    isCode: true
                )
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(HebdoTheme.codeBg))
            .padding(.vertical, 4)

        case .callout:
            HStack(alignment: .top, spacing: 10) {
                Button {
                    cycleCalloutKind(at: idx)
                } label: {
                    Text(MarkdownBlocks.calloutIcons[block.kind] ?? "💡")
                        .font(.system(size: 17))
                }
                .buttonStyle(.plain)

                blockEditor(
                    at: idx,
                    placeholder: "Callout",
                    font: HebdoFonts.serif(size: 16)
                )
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 8).fill(HebdoTheme.calloutBg))
            .padding(.vertical, 4)

        case .quote:
            HStack(alignment: .top, spacing: 12) {
                Rectangle()
                    .fill(HebdoTheme.text)
                    .frame(width: 3)
                blockEditor(
                    at: idx,
                    placeholder: "Quote",
                    font: HebdoFonts.serif(size: 16)
                )
            }
            .padding(.vertical, 4)

        case .todo:
            HStack(alignment: .top, spacing: 9) {
                Button {
                    guard idx < blocks.count else { return }
                    blocks[idx].checked.toggle()
                    scheduleSave()
                } label: {
                    Image(systemName: block.checked ? "checkmark.square.fill" : "square")
                        .font(.system(size: 18))
                        .foregroundStyle(block.checked ? HebdoTheme.accent : HebdoTheme.muted)
                        .padding(.top, 1)
                }
                .buttonStyle(.plain)

                blockEditor(
                    at: idx,
                    placeholder: "To-do",
                    font: HebdoFonts.serif(size: 16),
                    color: block.checked ? HebdoTheme.faint : HebdoTheme.text,
                    strikethrough: block.checked
                )
            }
            .padding(.leading, CGFloat(block.indent) * 20)
            .padding(.vertical, 2)

        case .ul:
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .font(.system(size: 18, weight: .bold, design: .serif))
                    .foregroundStyle(HebdoTheme.text)
                    .frame(width: 16, alignment: .center)
                blockEditor(
                    at: idx,
                    placeholder: "List",
                    font: HebdoFonts.serif(size: 16)
                )
            }
            .padding(.leading, CGFloat(block.indent) * 20)
            .padding(.vertical, 2)

        case .ol:
            HStack(alignment: .top, spacing: 6) {
                Text("\(orderedNumber(at: idx)).")
                    .font(.system(size: 16, design: .serif))
                    .foregroundStyle(HebdoTheme.text)
                    .frame(minWidth: 20, alignment: .trailing)
                blockEditor(
                    at: idx,
                    placeholder: "List",
                    font: HebdoFonts.serif(size: 16)
                )
            }
            .padding(.leading, CGFloat(block.indent) * 20)
            .padding(.vertical, 2)

        case .h1:
            blockEditor(
                at: idx,
                placeholder: "Heading 1",
                font: HebdoFonts.serif(size: 26, weight: .bold)
            )
            .padding(.top, 14)
            .padding(.bottom, 2)

        case .h2:
            blockEditor(
                at: idx,
                placeholder: "Heading 2",
                font: HebdoFonts.serif(size: 21, weight: .semibold)
            )
            .padding(.top, 12)
            .padding(.bottom, 2)

        case .h3:
            blockEditor(
                at: idx,
                placeholder: "Heading 3",
                font: HebdoFonts.serif(size: 18, weight: .semibold)
            )
            .padding(.top, 8)
            .padding(.bottom, 2)

        case .p:
            blockEditor(
                at: idx,
                placeholder: idx == blocks.count - 1 ? "Write something, or type # / - / []…" : "",
                font: HebdoFonts.serif(size: 16)
            )
            .padding(.vertical, 3)
        }
    }

    // MARK: - Block Editing Interactions

    private func focus(_ id: UUID, cursor: Int? = nil) {
        focusedBlockID = id
        if let cursor {
            pendingCursorBlockID = id
            pendingCursorOffset = cursor
        }
    }

    private func handleTextChange(at idx: Int, newVal: String) {
        // Multi-line paste into a non-code block: split cleanly into blocks
        if blocks[idx].type != .code, newVal.contains("\n") {
            let lines = newVal.replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .components(separatedBy: "\n")
            blocks[idx].text = lines.first ?? ""
            let nextType: BlockType = blocks[idx].type.isList ? blocks[idx].type : .p
            let nextIndent = blocks[idx].type.isList ? blocks[idx].indent : 0
            var lastID = blocks[idx].id
            for (offset, line) in lines.dropFirst().enumerated() {
                let nb = NoteBlock(type: nextType, text: line, indent: nextIndent)
                blocks.insert(nb, at: idx + 1 + offset)
                lastID = nb.id
            }
            focus(lastID, cursor: (lines.last ?? "").utf16.count)
            scheduleSave()
            return
        }

        // Live Markdown shortcuts as you type (exact desktop parity)
        if blocks[idx].type == .p {
            let shortcuts: [(String, BlockType)] = [
                ("### ", .h3), ("## ", .h2), ("# ", .h1),
                ("[] ", .todo), ("[ ] ", .todo),
                ("- ", .ul), ("* ", .ul), ("1. ", .ol),
                ("> ", .quote),
            ]
            for (prefix, targetType) in shortcuts where newVal.hasPrefix(prefix) {
                let rest = String(newVal.dropFirst(prefix.count))
                blocks[idx].type = targetType
                blocks[idx].text = rest
                focus(blocks[idx].id, cursor: rest.utf16.count)
                scheduleSave()
                return
            }
            if newVal == "---" {
                blocks[idx].type = .divider
                blocks[idx].text = ""
                let after = NoteBlock(type: .p)
                blocks.insert(after, at: idx + 1)
                focus(after.id, cursor: 0)
                scheduleSave()
                return
            }
            if newVal == "```" {
                blocks[idx].type = .code
                blocks[idx].text = ""
                focus(blocks[idx].id, cursor: 0)
                scheduleSave()
                return
            }
        }

        blocks[idx].text = newVal
        scheduleSave()
    }

    private func handleReturn(at idx: Int, head: String, tail: String) {
        let cur = blocks[idx]
        // Pressing Return on an empty list / quote / callout exits that block back to plain text
        if (cur.type.isList || cur.type == .quote || cur.type == .callout),
           head.trimmingCharacters(in: .whitespaces).isEmpty && tail.isEmpty {
            blocks[idx].type = .p
            blocks[idx].indent = 0
            blocks[idx].checked = false
            blocks[idx].text = ""
            focus(blocks[idx].id, cursor: 0)
            scheduleSave()
            return
        }

        blocks[idx].text = head
        let nextType: BlockType = cur.type.isList ? cur.type : .p
        let nextIndent = cur.type.isList ? cur.indent : 0
        let nb = NoteBlock(type: nextType, text: tail, indent: nextIndent)
        blocks.insert(nb, at: idx + 1)
        focus(nb.id, cursor: 0)
        scheduleSave()
    }

    private func handleBackspaceAtStart(at idx: Int) {
        guard idx < blocks.count else { return }
        let cur = blocks[idx]

        // 1. Outdent nested list item first
        if cur.indent > 0 {
            blocks[idx].indent -= 1
            scheduleSave()
            return
        }

        // 2. Strip block formatting (checkbox, bullet, heading, quote, callout, empty code) -> plain paragraph
        if cur.type != .p {
            if cur.type == .code && !cur.text.isEmpty { return }
            blocks[idx].type = .p
            blocks[idx].checked = false
            focus(blocks[idx].id, cursor: 0)
            scheduleSave()
            return
        }

        // 3. Plain paragraph at start: merge with previous block (or delete preceding divider)
        guard idx > 0 else { return }
        if blocks[idx - 1].type == .divider {
            blocks.remove(at: idx - 1)
            scheduleSave()
            return
        }
        let joinPos = blocks[idx - 1].text.utf16.count
        let prevID = blocks[idx - 1].id
        if !cur.text.isEmpty {
            blocks[idx - 1].text += cur.text
        }
        blocks.remove(at: idx)
        focus(prevID, cursor: joinPos)
        scheduleSave()
    }

    private func typeButton(_ type: BlockType, icon: String, label: String) -> some View {
        Button {
            applyBlockType(type)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16))
                .accessibilityLabel(label)
        }
    }

    private func applyBlockType(_ type: BlockType) {
        guard let fid = focusedBlockID, let idx = blocks.firstIndex(where: { $0.id == fid }) else {
            let nb = NoteBlock(type: type)
            blocks.append(nb)
            if type == .divider {
                let p = NoteBlock(type: .p)
                blocks.append(p)
                focus(p.id, cursor: 0)
            } else {
                focus(nb.id, cursor: 0)
            }
            scheduleSave()
            return
        }
        if type == .divider {
            blocks.insert(NoteBlock(type: .divider), at: idx + 1)
            let p = NoteBlock(type: .p)
            blocks.insert(p, at: idx + 2)
            focus(p.id, cursor: 0)
        } else {
            blocks[idx].type = (blocks[idx].type == type) ? .p : type
            if blocks[idx].type == .p {
                blocks[idx].checked = false
                blocks[idx].indent = 0
            }
            focus(blocks[idx].id, cursor: blocks[idx].text.utf16.count)
        }
        scheduleSave()
    }

    private func cycleCalloutKind(at idx: Int) {
        guard idx < blocks.count else { return }
        let kinds = MarkdownBlocks.calloutKinds
        let cur = kinds.firstIndex(of: blocks[idx].kind) ?? 0
        blocks[idx].kind = kinds[(cur + 1) % kinds.count]
        scheduleSave()
    }

    private func deleteBlock(at idx: Int) {
        guard idx < blocks.count else { return }
        blocks.remove(at: idx)
        if blocks.isEmpty { blocks.append(NoteBlock(type: .p)) }
        scheduleSave()
    }

    private func appendOrFocusLast() {
        if let last = blocks.last, last.type == .p && last.text.isEmpty {
            focus(last.id, cursor: 0)
        } else {
            let nb = NoteBlock(type: .p)
            blocks.append(nb)
            focus(nb.id, cursor: 0)
        }
    }

    private func orderedNumber(at idx: Int) -> Int {
        var n = 1
        var i = idx - 1
        while i >= 0 && blocks[i].type.isList {
            if blocks[i].type == .ol && blocks[i].indent == blocks[idx].indent { n += 1 }
            i -= 1
        }
        return n
    }

    // MARK: - Load / Save / Rename

    private func loadNote() {
        if let template = draftTemplate, !store.exists(currentPath) {
            let parsed = MarkdownBlocks.parse(template)
            blocks = parsed
            lastSavedMd = MarkdownBlocks.serialize(parsed)
            isDraft = true
        } else {
            let loaded = store.readNote(at: currentPath)
            let parsed = MarkdownBlocks.parse(loaded)
            blocks = parsed
            lastSavedMd = MarkdownBlocks.serialize(parsed)
            isDraft = false
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            flushSave()
        }
    }

    private func flushSave() {
        saveTask?.cancel()
        saveTask = nil
        let md = MarkdownBlocks.serialize(blocks)
        if md == lastSavedMd { return }
        store.writeNote(at: currentPath, content: md)
        lastSavedMd = md
        isDraft = false
    }

    private func commitRename() {
        let trimmed = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if isDraft { flushSave() }
        if let updated = store.renameNote(from: currentPath, to: trimmed) {
            currentPath = updated
        }
    }
}
