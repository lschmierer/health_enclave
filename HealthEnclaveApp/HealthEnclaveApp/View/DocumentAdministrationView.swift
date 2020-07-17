//
//  DocumentAdministrationView.swift
//  HealthEnclaveApp
//
//  Created by Lukas Schmierer on 17.07.20.
//  Copyright © 2020 Lukas Schmierer. All rights reserved.
//
import os
import SwiftUI

import HealthEnclaveCommon

extension HealthEnclave_DocumentMetadata: Identifiable {}

struct DocumentAdministrationView: View {
    @EnvironmentObject private var model: ApplicationModel
    @State var documents = [HealthEnclave_DocumentMetadata]()
    
    @State private var askDelete = false
    @State private var askDeleteMetadata: HealthEnclave_DocumentMetadata?
    
    var body: some View {
        return List(documents) { document in
            HStack {
                VStack(alignment: .leading) {
                    Text(document.name)
                    HStack {
                        Text(dateFormat(document.createdAt.date))
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        Spacer()
                        Text(document.createdBy)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
                Spacer().frame(width: 20)
                Button("Delete", action: {
                    askDelete = true
                    askDeleteMetadata = document
                })
                .font(.subheadline)
                .buttonStyle(BorderlessButtonStyle())
                .padding(4)
                .foregroundColor(.white)
                .background(Color.red)
                .cornerRadius(8)
            }
        }
        .onAppear {
            documents = model.localDocuments()
        }
        .alert(isPresented: $askDelete) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
            return Alert(title: Text("Delete \(askDeleteMetadata!.name) ?"),
                         message: Text("\(askDeleteMetadata!.name)\n\(dateFormatter.string(from: askDeleteMetadata!.createdAt.date))\n\(askDeleteMetadata!.createdBy)"),
                         primaryButton: .default(Text("Yes")) {
                            model.deleteLocalDocument(with: askDeleteMetadata!.id)
                            documents = model.localDocuments()
                         },
                         secondaryButton: .cancel(Text("No")))
        }
    }
    
    func dateFormat(_ date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        return dateFormatter.string(from: date)
    }
}
