//
//  ConnectView.swift
//  HealthEnclaveApp
//
//  Created by Lukas Schmierer on 06.07.20.
//  Copyright © 2020 Lukas Schmierer. All rights reserved.
//
import os
import Combine
import SwiftUI

import CarBode

struct ConnectView: View {
    @EnvironmentObject private var model: ApplicationModel
    @State private var lastQrData: String?
    
    @State private var showAlert = false
    @State private var alertTitle: String?
    @State private var alertMessage: String?
    
    @State private var connectSubscription: Cancellable?
    
    var body: some View {
        ZStack {
            Color.black
            if model.isConnected {
                VStack(spacing: 40) {
                    ActivityIndicator(isAnimating: .constant(true))
                    Text("Connected to Terminal\nTransfering data...")
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    Button("Disconnect", action: model.disconnect)
                        .fixedSize()
                        .padding()
                        .foregroundColor(.white)
                        .background(Color.blue)
                        .cornerRadius(8)
                    Text("Please keep the app in\nforeground to continue data transfer.")
                        .foregroundColor(.white)
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
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            self.lastQrData = nil
                        }
                        
                        self.connectSubscription = self.model.connect(to: data)
                            .receive(on: DispatchQueue.main)
                            .sink(receiveCompletion: { completion in
                            if case let .failure(error) = completion {
                                self.showAlert = true
                                self.alertTitle = "Connection error"
                                self.alertMessage = error.localizedDescription
                            }
                        }, receiveValue: { client in
                            self.lastQrData = nil
                        })
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

struct ConnectView_Previews: PreviewProvider {
    class ApplicationModelMock: ApplicationModel {
        override init() {
            super.init()
            self.isConnecting = false
            self.isConnected = true
        }
    }
    
    static var previews: some View {
        ConnectView().environmentObject(ApplicationModelMock())
    }
}

