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
    @EnvironmentObject private var model: ApplicationModel
    
    var body: some View {
        NavigationView {
            if model.deviceKey == nil {
                SetupView()
                    .navigationBarTitle("Setup")
            } else {
                ConnectView()
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView().environmentObject(ApplicationModel())
    }
}
