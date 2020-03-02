//
//  ContentView.swift
//  HealthEnclaveApp
//
//  Created by Lukas Schmierer on 02.03.20.
//  Copyright © 2020 Lukas Schmierer. All rights reserved.
//

import SwiftUI
import HealthEnclaveCommon

struct ContentView: View {
    var body: some View {
        Text("Hello, \(helloHealthEnclaveCommon)!")
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
