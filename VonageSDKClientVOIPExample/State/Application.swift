//
//  ApplicationState.swift
//  VonageSDKClientVOIPExample
//
//  Created by Ashley Arthur on 01/02/2023.
//

import Foundation
import Combine
import PushKit
import UIKit
import VonageClientSDKVoice


// MARK: Application Models

/// We define some general application concepts like connectivity and users.
/// Its assumed applications intergrating the Client SDK will have this define already

enum Connection {
    case unknown
    case connected
    case reconnecting
    case disconnected(err:Error?)
}

struct User {
    let info: UserDetails
    let token: String
}

// MARK: Application State

class ApplicationState: NSObject, UserIdentityDelegate, PKPushRegistryDelegate {

    // private deps
    private let identity: UserIdentityManager
    private let voipRegistry = PKPushRegistry(queue: nil)

    // public
    lazy var user = CurrentValueSubject<User?, Never>(nil)
    
    lazy var vonageServiceToken = user
        .compactMap { $0 }
        .combineLatest(
            NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification).map { _ in true }.prepend(true)
        )
        .flatMap { (u:User,_) in
            Future<String,Error>{ p in
                self.identity.getServiceToken(name: u.token) { token in
                    p(Result.success(token))
                }
            }
        }
    
    let deviceToken = Deferred {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
        return NotificationCenter.default
            .publisher(for: NSNotification.didRegisterForRemoteNotificationNotification)
            .map { n  in n.userInfo!["data"] as? Data}
    }
        .multicast(subject: CurrentValueSubject<Data?,Never>(nil))
        .autoconnect()
        .compactMap { $0 }
    
    
    lazy var voipToken = Just(nil).handleEvents(receiveSubscription: { _ in
        self.voipRegistry.delegate = self
        self.voipRegistry.desiredPushTypes = [PKPushType.voIP]
    })
        .multicast(subject: CurrentValueSubject<Data?,Never>(nil))
        .autoconnect()
        .merge(with: voipTokenCache)
        .compactMap { $0 }

    
    // -----

    init(vonageClient: VGVoiceClient, identity: UserIdentityManager) {
        self.identity = identity
        super.init()
        self.identity.delgate = self
    }
    
    // MARK: PUSH
    private let voipTokenCache = CurrentValueSubject<Data?,Never>(nil)
    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        if (type == PKPushType.voIP) {
            voipTokenCache.send(pushCredentials.token)
        }
    }
    
    // MARK: UserIdentityDelegate
    func userAuthorised(userToken: String, userData: UserDetails) {
        let user = User(info: userData, token: userToken)
        self.user.send(user)
    }

    func userAuthRevoked() {
        self.user.send(nil)
    }
}
