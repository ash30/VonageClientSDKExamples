//
//  AppDelegate+Startup.swift
//  VonageSDKClientVOIPExample
//
//  Created by Ashley Arthur on 06/02/2023.
//

import Foundation
import UIKit
import Combine

extension AppDelegate {
    
    func setupCPAASConnectivity() {
        
        self.applicationState.user
            .combineLatest(
                NotificationCenter.default.publisher(
                    for: UIApplication.willEnterForegroundNotification
                ).map { _ in true }.prepend(true)
            )
            .filter { user, _ in user != nil }
            .repeating(attempts: 10){_,n -> AnyPublisher<Void, Never> in
                Just(())
                .delay(for: .seconds(10*n), scheduler: RunLoop.main, options: .none)
                .eraseToAnyPublisher()
            }
            .prefix(untilOutputFrom: self.applicationCPAASState.session.dropFirst(1).filter{ $0 != nil })
            .sink { _ in
                NotificationCenter.default.post(name: ApplicationCallState.CallStateConnectionStart, object:nil, userInfo:nil)
            }.store(in: &cancellables)
        
        
        
        
        // On each application foregound evejt, we restart the CPAAS Connection
        // IFF the application's user is currently authenticated 
//        self.applicationState.user.filter { $0 != nil }
//            .combineLatest(
//                NotificationCenter.default.publisher(
//                            for: UIApplication.willEnterForegroundNotification
//                ).map { _ in true }.prepend(true)
//            )
//            .flatMap { _ in
//                Just(true)
//                    .merge(with: self.applicationCPAASState.session
//                        .dropFirst(1)
//                        .removeDuplicates()
//                        .filter { $0 == nil }
//                        .map { _ in true}
//                    )
//            }
//            .map { _ in
//                // a simple back off for our retries
//                Array(0...10)
//                    .publisher
//                    .map { (n:Int) -> AnyPublisher<Bool,Never> in
//                        Timer.publish(every: TimeInterval(n * 10), on: .main, in: .common)
//                            .autoconnect().first().map { _ in true }
//                            .eraseToAnyPublisher()
//                    }
//                    .flatMap(maxPublishers: Subscribers.Demand.max(1), { $0 })
//                    // Keep going until we have an active session
//                    .prefix(untilOutputFrom: self.applicationCPAASState.session.dropFirst(1).filter { $0 != nil })
//            }
//            .switchToLatest()
//            .sink { _ in
//                NotificationCenter.default.post(name: ApplicationCallState.CallStateConnectionStart, object:nil, userInfo:nil)
//            }.store(in: &cancellables)
        
    }
    
    func start() {

        setupCPAASConnectivity()
        
    }
    
}

