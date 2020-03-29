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
    @State var model = ApplicationModel()
    @State var connecting = false
    
    var body: some View {
        ZStack {
            if model.isConnected {
                VStack(spacing: 40) {
                    ActivityIndicator(isAnimating: .constant(true))
                    Text("Connected to Terminal\nTransfering data...")
                        .multilineTextAlignment(.center)
                    Button("Disconnect", action: {
                        
                    })
                        .padding()
                        .foregroundColor(.white)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
            } else {
                CBScanner(supportBarcode: [.qr])
                    .interval(delay: 0)
                    .found(r: {
                        if(!self.connecting) {
                            self.connecting = true
                            self.model.connect(to: $0)
                        }
                    })
                VStack(spacing: 40) {
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
                }
            }
        }
        .edgesIgnoringSafeArea(.all)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
