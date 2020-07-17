//
//  SetupView.swift
//  HealthEnclaveApp
//
//  Created by Lukas Schmierer on 06.07.20.
//  Copyright © 2020 Lukas Schmierer. All rights reserved.
//

import SwiftUI

enum SetupType {
    case setup
    case recover
}

struct SetupView: View {
    @EnvironmentObject private var model: ApplicationModel
    @State private var setupType: SetupType?
    @State private var recoverySeed: String = ""
    
    @State private var showAlert = false
    @State private var alertTitle: String?
    @State private var alertMessage: String?
    
    var body: some View {
        switch setupType {
        case .setup:
            if let mnemonicPhrase = self.model.mnemonicPhrase {
                return AnyView(VStack {
                    Spacer()
                    Text("Please take note of the\nfollowing phrase and\nstore it somewhere safe:")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Spacer().frame(height: 40)
                    ForEach(0..<3) { row in
                        HStack() {
                            ForEach(0..<4) { cell in
                                Text(mnemonicPhrase[row * 4 + cell])
                            }
                        }
                    }
                    Spacer()
                    Button("I have created a Backup", action: {
                        try! self.model.setDeviceKey(from: mnemonicPhrase)
                    })
                    .fixedSize()
                    .padding()
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .foregroundColor(.white)
                    .background(Color.red)
                    .cornerRadius(8)
                    .padding(20)
                })
            } else {
                return AnyView(ActivityIndicator(isAnimating: .constant(true)))
            }
        case .recover:
            return AnyView(VStack {
                Spacer()
                Text("Enter recovery seed:")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Spacer().frame(height: 40)
                TextEditor(text: $recoverySeed)
                    .border(Color.black)
                    .frame(height: 100)
                    .padding(20)
                Spacer()
                Button("Restore Backup", action: {
                    do {
                        try self.model.setDeviceKey(from: recoverySeed
                                                        .lowercased()
                                                        .split(whereSeparator: \.isNewline)
                                                        .flatMap({ $0.split(whereSeparator: \.isWhitespace) })
                                                        .map({ String($0) }))
                    } catch {
                        self.showAlert = true
                        self.alertTitle = "Invalid Recovery Phrase"
                        self.alertMessage = error.localizedDescription
                    }
                })
                .disabled(recoverySeed.isEmpty)
                .fixedSize()
                .padding()
                .frame(minWidth: 0, maxWidth: .infinity)
                .foregroundColor(.white)
                .background(Color.blue)
                .cornerRadius(8)
                .padding(20)
            }
            .padding()
            .keyboardAdaptive()
            .alert(isPresented: $showAlert) {
                Alert(title: Text(alertTitle ?? ""), message: Text(alertMessage ?? ""))
            })
        default:
            return AnyView(VStack {
                Button("Setup", action: {
                    self.setupType = .setup
                    self.model.generateMnemonic()
                })
                .fixedSize()
                .padding()
                .frame(minWidth: 0, maxWidth: .infinity)
                .foregroundColor(.white)
                .background(Color.blue)
                .cornerRadius(8)
                .padding(20)
                Button("Recover", action: {
                    self.setupType =  .recover
                })
                .fixedSize()
                .padding()
                .frame(minWidth: 0, maxWidth: .infinity)
                .foregroundColor(.white)
                .background(Color.blue)
                .cornerRadius(8)
                .padding(20)
            })
        }
    }
}

struct SetupView_Previews: PreviewProvider {
    static var previews: some View {
        SetupView().environmentObject(ApplicationModel())
    }
}
