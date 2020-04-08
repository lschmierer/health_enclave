//
//  ContentView.swift
//  HealthEnclaveApp
//
//  Created by Lukas Schmierer on 02.03.20.
//  Copyright © 2020 Lukas Schmierer. All rights reserved.
//

import SwiftUI
import CarBode

//import HealthEnclaveCommon

struct ContentView: View {
    @ObservedObject var model: ApplicationModel
    @State var lastQrData: String?
    @State var showAlert = false
    @State var alertTitle: String?
    @State var alertMessage: String?
    
    var body: some View {
        ZStack {
            if model.isConnected {
                VStack(spacing: 40) {
                    ActivityIndicator(isAnimating: .constant(true))
                    Text("Connected to Terminal\nTransfering data...")
                        .multilineTextAlignment(.center)
                    Button("Disconnect", action: model.disconnect)
                        .padding()
                        .foregroundColor(.white)
                        .background(Color.blue)
                        .cornerRadius(8)
                    Text("Please leave the app in the\nforeground while data is\nbeing transferred.")
                        .multilineTextAlignment(.center)
                }
            } else {
                CBScanner(supportBarcode: [.qr])
                    .interval(delay: 0.2)
                    .found { data in
                        if self.model.isConnecting || data == self.lastQrData {
                            return
                        }
                        self.lastQrData = data
                        self.model.connect(to: data) { result in
                            if case let .failure(error) = result {
                                self.showAlert = true
                                self.alertTitle = "Connection error"
                                self.alertMessage = error.localizedDescription
                            } else {
                                self.lastQrData = nil
                            }
                        }
                }
                VStack(spacing: 40) {
                    if(!model.isConnecting) {
                    Rectangle()
                        .stroke(Color.white, style: StrokeStyle(
                            lineWidth: 4,
                            lineCap: .round,
                            lineJoin: .round,
                            dash: [30, 120, 30, 0]))
                        .frame(width: 180, height: 180)
                    Text("Please Scan\nTerminal QR Code")
                        .foregroundColor(Color.white)
                        .multilineTextAlignment(.center)
                        .shadow(radius: 4)
                    } else {
                        ActivityIndicator(isAnimating: .constant(true))
                        Text("Connecting...")
                            .foregroundColor(Color.white)
                            .multilineTextAlignment(.center)
                            .shadow(radius: 4)
                    }
                }
            }
        }
        .edgesIgnoringSafeArea(.all)
        .alert(isPresented: $showAlert) {
            Alert(title: Text(alertTitle ?? ""), message: Text(alertMessage ?? ""))
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    class ApplicationModelMock: ApplicationModel {
        override init() {
            super.init()
            self.isConnecting = true
            self.isConnected = false
        }
    }
    
    static var previews: some View {
        ContentView(model: ApplicationModelMock())
    }
}
