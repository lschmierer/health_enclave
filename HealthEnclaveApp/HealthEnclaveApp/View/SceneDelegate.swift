//
//  SceneDelegate.swift
//  HealthEnclaveApp
//
//  Created by Lukas Schmierer on 02.03.20.
//  Copyright © 2020 Lukas Schmierer. All rights reserved.
//

import os
import UIKit
import SwiftUI

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    
    var window: UIWindow?
    
    func appModel() -> ApplicationModel {
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        return appDelegate.model
    }
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        let contentView = ContentView(model: appModel())
        
        // Use a UIHostingController as window root view controller.
        if let windowScene = scene as? UIWindowScene {
            let window = UIWindow(windowScene: windowScene)
            window.rootViewController = UIHostingController(rootView: contentView)
            self.window = window
            window.makeKeyAndVisible()
        }
    }
    
    func sceneDidBecomeActive(_ scene: UIScene) {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
    
    func sceneDidEnterBackground(_ scene: UIScene) {
        let model = appModel()
        if model.isConnected && model.isTransfering {
            sendOpenForegroundNotification()
        }
    }
    
    func sendOpenForegroundNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Keep Health Enclave in foreground"
        content.body = "Please keep the Health Enclave in foreground to continue data transferred."
        content.sound = UNNotificationSound.defaultCritical
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        
        let request = UNNotificationRequest(identifier: "testNotification", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { (error) in
            if let error = error {
                os_log(.info, "Notification error: %@", error.localizedDescription)
            }
        }
    }
}

