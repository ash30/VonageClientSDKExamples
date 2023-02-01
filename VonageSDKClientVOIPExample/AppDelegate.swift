//
//  AppDelegate.swift
//  VonageSDKClientVOIPExample
//
//  Created by Ashley Arthur on 25/01/2023.
//

import UIKit
import VonageClientSDKVoice
import CallKit


// We should add this to sdk
extension VGSessionErrorReason: Error {}


@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    public var identity: UserIdentityManager!
    public var applicationState: ApplicationState!
    public var appplicationCallState: ApplicationCallState!
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Create Application Object Graph
        VGBaseClient.setDefaultLoggingLevel(.verbose)
        let vonage = VGVoiceClient()
        vonage.setConfig(.init(region: .US))
        
        identity = DemoIdentityManager()
        applicationState = ApplicationState(vonageClient: vonage, identity: identity)
        appplicationCallState = ApplicationCallState(from: applicationState, and: vonage)
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
