import SwiftUI

struct NoteEditorView: View {
    @EnvironmentObject private var store: NoteStore

    let initialPath: String
    let draftTemplate: String?
    let allowTitleEdit: Bool

    @State private var currentPath: String
    @State private var titleText: String
    @State private var blocks: [NoteBlock] = []
    @State private var lastSavedMd: String = ""
    @State private var isDraft: Bool
    @State private var saveTask: Task<Void, Never>?
    @FocusState private var focusedBlockID: UUID?

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
            .frame(maxWidth: .infinity, alignment: .leading)
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

    @ViewBuilder
    private func blockRow(at idx: Int) -> some View {
        let block = blocks[idx]
        let binding = Binding<String>(
            get: { idx < blocks.count ? blocks[idx].text : "" },
            set: { newVal in
                guard idx < blocks.count else { return }
                handleTextChange(at: idx, newVal: newVal)
            }
        )

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
                TextField("Code…", text: binding, axis: .vertical)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(HebdoTheme.text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedBlockID, equals: block.id)
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

                TextField("Callout", text: binding, axis: .vertical)
                    .font(.system(size: 16, design: .serif))
                    .foregroundStyle(HebdoTheme.text)
                    .focused($focusedBlockID, equals: block.id)
                    .onSubmit { handleSubmit(at: idx) }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 8).fill(HebdoTheme.calloutBg))
            .padding(.vertical, 4)

        case .quote:
            HStack(alignment: .top, spacing: 12) {
                Rectangle()
                    .fill(HebdoTheme.text)
                    .frame(width: 3)
                TextField("Quote", text: binding, axis: .vertical)
                    .font(.system(size: 16, design: .serif))
                    .foregroundStyle(HebdoTheme.text)
                    .focused($focusedBlockID, equals: block.id)
                    .onSubmit { handleSubmit(at: idx) }
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
                        .padding(.top, 2)
                }
                .buttonStyle(.plain)

                TextField("To-do", text: binding, axis: .vertical)
                    .font(.system(size: 16, design: .serif))
                    .strikethrough(block.checked, color: HebdoTheme.faint)
                    .foregroundStyle(block.checked ? HebdoTheme.faint : HebdoTheme.text)
                    .focused($focusedBlockID, equals: block.id)
                    .onSubmit { handleSubmit(at: idx) }
            }
            .padding(.leading, CGFloat(block.indent) * 20)
            .padding(.vertical, 2)

        case .ul:
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .font(.system(size: 18, weight: .bold, design: .serif))
                    .foregroundStyle(HebdoTheme.text)
                    .frame(width: 16, alignment: .center)
                TextField("List", text: binding, axis: .vertical)
                    .font(.system(size: 16, design: .serif))
                    .foregroundStyle(HebdoTheme.text)
                    .focused($focusedBlockID, equals: block.id)
                    .onSubmit { handleSubmit(at: idx) }
            }
            .padding(.leading, CGFloat(block.indent) * 20)
            .padding(.vertical, 2)

        case .ol:
            HStack(alignment: .top, spacing: 6) {
                Text("\(orderedNumber(at: idx)).")
                    .font(.system(size: 16, design: .serif))
                    .foregroundStyle(HebdoTheme.text)
                    .frame(minWidth: 20, alignment: .trailing)
                TextField("List", text: binding, axis: .vertical)
                    .font(.system(size: 16, design: .serif))
                    .foregroundStyle(HebdoTheme.text)
                    .focused($focusedBlockID, equals: block.id)
                    .onSubmit { handleSubmit(at: idx) }
            }
            .padding(.leading, CGFloat(block.indent) * 20)
            .padding(.vertical, 2)

        case .h1:
            TextField("Heading 1", text: binding, axis: .vertical)
                .font(.system(size: 26, weight: .bold, design: .serif))
                .foregroundStyle(HebdoTheme.text)
                .padding(.top, 14)
                .padding(.bottom, 2)
                .focused($focusedBlockID, equals: block.id)
                .onSubmit { handleSubmit(at: idx) }

        case .h2:
            TextField("Heading 2", text: binding, axis: .vertical)
                .font(.system(size: 21, weight: .semibold, design: .serif))
                .foregroundStyle(HebdoTheme.text)
                .padding(.top, 12)
                .padding(.bottom, 2)
                .focused($focusedBlockID, equals: block.id)
                .onSubmit { handleSubmit(at: idx) }

        case .h3:
            TextField("Heading 3", text: binding, axis: .vertical)
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundStyle(HebdoTheme.text)
                .padding(.top, 8)
                .padding(.bottom, 2)
                .focused($focusedBlockID, equals: block.id)
                .onSubmit { handleSubmit(at: idx) }

        case .p:
            TextField(idx == blocks.count - 1 ? "Write something, or type # / - / []…" : "", text: binding, axis: .vertical)
                .font(.system(size: 16, design: .serif))
                .foregroundStyle(HebdoTheme.text)
                .padding(.vertical, 3)
                .focused($focusedBlockID, equals: block.id)
                .onSubmit { handleSubmit(at: idx) }
        }
    }

    // MARK: - Block Editing Interactions

    private func handleTextChange(at idx: Int, newVal: String) {
        // Pressing Return inside a vertical TextField inserts "\n" — split into a new block!
        if blocks[idx].type != .code, newVal.contains("\n") {
            let parts = newVal.components(separatedBy: "\n")
            let head = parts[0]
            let tail = parts.dropFirst().joined(separator: " ")
            if blocks[idx].type.isList && head.trimmingCharacters(in: .whitespaces).isEmpty && tail.isEmpty {
                blocks[idx].type = .p
                blocks[idx].text = ""
                scheduleSave()
                return
            }
            blocks[idx].text = head
            let nextType: BlockType = blocks[idx].type.isList ? blocks[idx].type : .p
            let nb = NoteBlock(type: nextType, text: tail, indent: blocks[idx].type.isList ? blocks[idx].indent : 0)
            blocks.insert(nb, at: idx + 1)
            focusedBlockID = nb.id
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
                blocks[idx].type = targetType
                blocks[idx].text = String(newVal.dropFirst(prefix.count))
                scheduleSave()
                return
            }
            if newVal == "---" {
                blocks[idx].type = .divider
                blocks[idx].text = ""
                let after = NoteBlock(type: .p)
                blocks.insert(after, at: idx + 1)
                focusedBlockID = after.id
                scheduleSave()
                return
            }
            if newVal == "```" {
                blocks[idx].type = .code
                blocks[idx].text = ""
                scheduleSave()
                return
            }
        }

        blocks[idx].text = newVal
        scheduleSave()
    }

    private func handleSubmit(at idx: Int) {
        guard idx < blocks.count else { return }
        if blocks[idx].type.isList && blocks[idx].text.trimmingCharacters(in: .whitespaces).isEmpty {
            blocks[idx].type = .p
            scheduleSave()
            return
        }
        let nextType: BlockType = blocks[idx].type.isList ? blocks[idx].type : .p
        let nb = NoteBlock(type: nextType, indent: blocks[idx].type.isList ? blocks[idx].indent : 0)
        blocks.insert(nb, at: idx + 1)
        focusedBlockID = nb.id
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
                focusedBlockID = p.id
            } else {
                focusedBlockID = nb.id
            }
            scheduleSave()
            return
        }
        if type == .divider {
            blocks.insert(NoteBlock(type: .divider), at: idx + 1)
            let p = NoteBlock(type: .p)
            blocks.insert(p, at: idx + 2)
            focusedBlockID = p.id
        } else {
            blocks[idx].type = (blocks[idx].type == type) ? .p : type
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
            focusedBlockID = last.id
        } else {
            let nb = NoteBlock(type: .p)
            blocks.append(nb)
            focusedBlockID = nb.id
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
