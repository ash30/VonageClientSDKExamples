////
////  ApplicationState.swift
////  VonageSDKClientVOIPExample
////
////  Created by Ashley Arthur on 01/02/2023.
////
//
//import Foundation
//import Combine
//import PushKit
//import UIKit
//import VonageClientSDKVoice
//import CallKit
//
//
//// MARK: Application Models
//
///// We define some general application concepts like connectivity and users.
///// Its assumed applications intergrating the Client SDK will have this define already
//
//enum Connection {
//    case connected
//    case error(err:Error?)
//    case reconnecting
//    case disconnected(err:Error?)
//}
//
//
//
//enum ApplicationErrors: Error {
//    case PushNotRegistered
//    case Unauthorised
//    case unknown
//}
//// MARK: Application State
//
////class ApplicationState: NSObject, UserIdentityDelegate, PKPushRegistryDelegate {
//
//    private let identity: UserIdentityManager
//    private let vonage: VGVoiceClient
//    private let voipRegistry = PKPushRegistry(queue: nil)
//    private var cancellables = Set<AnyCancellable>()
//
//    // public
//    lazy var user = CurrentValueSubject<User?, Never>(nil)
//    
//    lazy var vonageServiceToken = self.user
//        .flatMap { user in
//            Future<String,Error>{ p in
//                user.map { u in
//                    self.identity.getServiceToken(name: u.token) { token in
//                        p(Result.success(token))
//                    }
//                } ?? p(Result.failure(ApplicationErrors.Unauthorised))
//            }.eraseToAnyPublisher()
//        }
//        .first()
//    
//    let deviceToken = Deferred {
//        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
//            if granted {
//                DispatchQueue.main.async {
//                    UIApplication.shared.registerForRemoteNotifications()
//                }
//            }
//        }
//        return NotificationCenter.default
//            .publisher(for: NSNotification.didRegisterForRemoteNotificationNotification)
//            .map { n  in n.userInfo!["data"] as? Data}
//    }
//        .multicast(subject: CurrentValueSubject<Data?,Never>(nil))
//        .autoconnect()
//        .compactMap { $0 }
//    
//    
//    lazy var voipToken = Just(nil).handleEvents(receiveSubscription: { _ in
//        self.voipRegistry.delegate = self
//        self.voipRegistry.desiredPushTypes = [PKPushType.voIP]
//    })
//        .multicast(subject: CurrentValueSubject<Data?,Never>(nil))
//        .autoconnect()
//        .merge(with: voipTokenCache)
//        .compactMap { $0 }
//
//    
//    // -----
//
//    init(vonageClient: VGVoiceClient, identity: UserIdentityManager) {
//        self.identity = identity
//        self.vonage = vonageClient
//        super.init()
//        self.identity.delgate = self
//    }
//    
//    // MARK: PUSH
//    private let voipTokenCache = CurrentValueSubject<Data?,Never>(nil)
//    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
//        if (type == PKPushType.voIP) {
//            voipTokenCache.send(pushCredentials.token)
//        }
//    }
//    
//    let voipPush = PassthroughSubject<PKPushPayload,Never>()
//    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
//            
//        switch (type){
//        case .voIP:
//            voipPush.send(payload)
//        default:
//            return
//        }
//        completion()
//    }
//    
//    // MARK: UserIdentityDelegate
//    func userAuthorised(userToken: String, userData: UserDetails) {
//        let user = User(info: userData, token: userToken)
//        self.user.send(user)
//    }
//
//    private let userDidAuthRevoked = PassthroughSubject<Bool,Never>()
//    func userAuthRevoked() {
//        self.user.send(nil)
//    }
//    
//    
//
//    
//}
