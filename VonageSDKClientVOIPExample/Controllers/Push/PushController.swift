//
//  PushController.swift
//  VonageSDKClientVOIPExample
//
//  Created by Ashley Arthur on 12/02/2023.
//

import Foundation
import PushKit
import UIKit
import Combine
import UserNotifications

class PushController: NSObject {
    
    private let voipRegistry = PKPushRegistry(queue: nil)
    var cancellables = Set<AnyCancellable>()

    // Delegate Subjects
    let voipToken = PassthroughSubject<Data,Never>()
    let newVoipPush = PassthroughSubject<PKPushPayload,Never>()
    
    override init() {
        super.init()
    }
}

extension PushController: ApplicationController {
    
    func bindToApplicationState(_ state: ApplicationState) {
        
        // Notifications
        let pushInit = state.$user
            .compactMap {$0}
            .combineLatest(
                ApplicationAction
                    .publisher
                    .filter { if case .initialisePush = $0 { return true }; return false  }

            )
            .first()
            
        pushInit.sink { _ in
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    if granted {
                        DispatchQueue.main.async {
                            UIApplication.shared.registerForRemoteNotifications()
                        }
                    }
                }
            }
            .store(in: &self.cancellables)
        
        
        let deviceToken = NotificationCenter.default
            .publisher(for: NSNotification.didRegisterForRemoteNotificationNotification)
            .compactMap { n  in n.userInfo!["data"] as? Data?}
            .first()
        
        deviceToken.assign(to: &state.$deviceToken)

        
        // VOIP
        let voipTokenInit =  ApplicationAction
            .publisher
            .filter { if case .initialisePush = $0 { return true }; return false  }
            .first()
        
        voipTokenInit.sink { _ in
                self.voipRegistry.delegate = self
                self.voipRegistry.desiredPushTypes = [PKPushType.voIP]
            }
            .store(in: &self.cancellables)
        
        self.voipToken.map { $0 as Data? }.assign(to: &state.$voipToken)
        self.newVoipPush.sink { state.voipPush.send($0)}.store(in: &self.cancellables)
    }
}
