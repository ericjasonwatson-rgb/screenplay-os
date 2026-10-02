import SwiftUI

/// A separate document section. Title-page editing never appends screenplay paragraphs.
struct ScreenplayTitlePageEditor: View {
    @ObservedObject var model: ScreenplayViewModel
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Title Page").font(.headline)
                Text("Separate from script page 1").foregroundStyle(.secondary)
                Spacer()
                Button("Done") { model.titlePagePresented = false }.keyboardShortcut(.cancelAction)
            }.padding(16)
            Divider()
            HStack(alignment: .top, spacing: 20) {
                Form {
                    TextField("Title", text: model.titlePageBinding(.title), axis: .vertical)
                    TextField("Subtitle / additional credits", text: model.titlePageBinding(.subtitle), axis: .vertical).lineLimit(4...10)
                    TextField("Written by", text: model.titlePageBinding(.author))
                    TextField("Contact", text: model.titlePageBinding(.contact), axis: .vertical).lineLimit(2...4)
                    TextField("Draft date", text: model.titlePageBinding(.draftDate))
                    if model.hasImportedTitlePageTail {
                        Text("An older import left six title-template lines at the end of this script.")
                        Button("Move Imported Title Text") { model.moveImportedTitlePageTail() }
                        Text("Keeps a safety snapshot and supports Undo.").font(.caption)
                    }
                }.frame(width: 290)
                ScrollView {
                    VStack(spacing: 18) {
                        Spacer().frame(height: 140)
                        Text(model.titlePage.title).multilineTextAlignment(.center)
                        if !model.titlePage.subtitle.isEmpty { Text(model.titlePage.subtitle).multilineTextAlignment(.center) }
                        if !model.titlePage.author.isEmpty {
                            Text("Written by\n\n" + model.titlePage.author).multilineTextAlignment(.center)
                        }
                        Spacer(minLength: 100)
                        HStack {
                            Text([model.titlePage.contact, model.titlePage.draftDate].filter { !$0.isEmpty }.joined(separator: "\n"))
                            Spacer()
                        }
                    }
                    .font(.custom("Courier", size: 12))
                    .padding(48).frame(width: 460).frame(minHeight: 596)
                    .foregroundStyle(.black).background(.white)
                }
            }.padding(20)
        }.frame(width: 810, height: 740)
        .background(ScreenplayOSTokens.Palette.workspaceBackground)
    }
}
