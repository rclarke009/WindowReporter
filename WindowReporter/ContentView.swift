//
//  ContentView.swift
//  WindowReporter
//
//  Created by Rebecca Clarke on 11/18/25.
//

import SwiftUI

struct ContentView: View {
    @Binding var document: WindowReporterDocument

    var body: some View {
        TextEditor(text: $document.text)
    }
}

#Preview {
    ContentView(document: .constant(WindowReporterDocument()))
}
