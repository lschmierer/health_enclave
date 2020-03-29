//
//  ActivityIndicator.swift
//  HealthEnclaveApp
//
//  Created by Lukas Schmierer on 20.03.20.
//  Copyright © 2020 Lukas Schmierer. All rights reserved.
//
import SwiftUI
import UIKit

public struct ActivityIndicator: UIViewRepresentable {
    public typealias UIViewType = UIActivityIndicatorView
    
    @Binding var isAnimating: Bool
    
    public func makeUIView(context: Context) -> UIViewType {
        UIActivityIndicatorView(style: .medium)
    }
    
    public func updateUIView(_ uiView: UIViewType, context: Context) {
        isAnimating ? uiView.startAnimating() : uiView.stopAnimating()
    }
}
