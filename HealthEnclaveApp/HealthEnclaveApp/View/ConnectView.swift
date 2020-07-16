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

import HealthEnclaveCommon

struct ConnectView: View {
    @EnvironmentObject private var model: ApplicationModel
    @State private var lastQrData: String?
    
    @State private var showConnectionError = false
    @State private var connectionError: ApplicationError?
    
    @State private var askAccessPermission = false
    @State private var askAccessDocumentMetadata: HealthEnclave_DocumentMetadata?
    
    var body: some View {
        var stack = AnyView(ZStack {
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
                        guard self.lastQrData != data else {
                            return
                        }
                        
                        self.lastQrData = data
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            self.lastQrData = nil
                        }
                        
                        self.model.connect(to: data)
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
        .alert(isPresented: $showConnectionError) {
            Alert(title: Text("Connection Error"), message: Text(connectionError!.localizedDescription))
        }
        .alert(isPresented: $askAccessPermission) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
            return Alert(title: Text("Terminal wants to access \(askAccessDocumentMetadata!.name)"),
                         message: Text("\(askAccessDocumentMetadata!.name)\n\(dateFormatter.string(from: askAccessDocumentMetadata!.createdAt.date))\n\(askAccessDocumentMetadata!.createdBy)"),
                         primaryButton: .default(Text("Allow")) {
                            model.documentsModel?.grantAccess(to: askAccessDocumentMetadata!.id)
                         },
                         secondaryButton: .cancel(Text("Don't allow")) {
                            model.documentsModel?.grantAccessNot(to: askAccessDocumentMetadata!.id)
                         })
        }
        .onReceive(model.$connectionError, perform: { error in
            if let error = error {
                showConnectionError = true
                self.connectionError = error
            }
        }))
        
        if let accessDocumentRequests = model.documentsModel?.accessDocumentRequests {
            stack = AnyView(stack.onReceive(accessDocumentRequests) { documentMetadata in
                self.askAccessPermission = true
                self.askAccessDocumentMetadata = documentMetadata
            })
        }
        
        return stack
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

