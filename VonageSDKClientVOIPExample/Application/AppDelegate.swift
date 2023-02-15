//
//  AppDelegate.swift
//  VonageSDKClientVOIPExample
//
//  Created by Ashley Arthur on 25/01/2023.
//

import UIKit
import VonageClientSDKVoice
import CallKit
import Combine


// We should add this to sdk


@main
class AppDelegate: UIResponder, UIApplicationDelegate {
        
    var controllers: [ApplicationController] = []
    var appState = ApplicationState()
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Create Application Object Graph
        VGBaseClient.setDefaultLoggingLevel(.verbose)
        let vonage = VGVoiceClient()
        vonage.setConfig(.init(region: .US))
        
        controllers.append(UserController())
        controllers.append(PushController())
        controllers.append(CallController(client: vonage))
        controllers.append(CallKitController(client: vonage))
        controllers.forEach { $0.bindToApplicationState(appState)}
        
        // Once APP is up, initalise Push things once we have a logged in user
        ApplicationAction.post(.initialisePush)
        
        ApplicationAction.post(.userAuth(uname: "", pword: ""))

                
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)        
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }
    
    // MARK: Notifications
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationCenter.default.post(name: NSNotification.didRegisterForRemoteNotificationNotification, object: nil, userInfo: ["data":deviceToken])
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NotificationCenter.default.post(name: NSNotification.didFailToRegisterForRemoteNotification, object: nil, userInfo: ["error":error])
    }
}


extension NSNotification {
    public static let didRegisterForRemoteNotificationNotification = NSNotification.Name("didRegisterForRemoteNotificationWithDeviceTokenNotification")
    public static let didFailToRegisterForRemoteNotification = NSNotification.Name("didFailToRegisterForRemoteNotificationsWithErrorNotification")

}
