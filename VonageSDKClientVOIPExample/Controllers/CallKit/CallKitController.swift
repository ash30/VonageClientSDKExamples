//
//  CallKitController.swift
//  VonageSDKClientVOIPExample
//
//  Created by Ashley Arthur on 14/02/2023.
//

import Foundation
import Combine
import VonageClientSDKVoice
import CallKit

class CallKitController: NSObject {
    
    private let client: VGVoiceClient
    private var cancellables = Set<AnyCancellable>()

    // Callkit
    lazy var callProvider = { () -> CXProvider in
        let provider = CXProvider(configuration: CXProviderConfiguration())
        provider.setDelegate(self, queue: nil)
        return provider
    }()
    lazy var callController = CXCallController()
    
    // Delegate methods as subjects
    let callkitAnswer = PassthroughSubject<CXAnswerCallAction,Never>()
    let callkitHangup = PassthroughSubject<CXEndCallAction,Never>()
    
    init(client: VGVoiceClient) {
        self.client = client
    }
}


extension CallKitController: ApplicationController {
    
    func bindToApplicationState(_ state: ApplicationState) {
        // Report New Calls to 
        state.newCalls
            .flatMap {
                $0.first()
            }
            .compactMap {
                if case let .inbound(id,from,_) = $0 {
                    let update = CXCallUpdate()
                    update.localizedCallerName = from
                    return (id ,update)
                }; return nil
            }
            .sink { (id,update) in
            self.callProvider.reportNewIncomingCall(with: id, update: update) { err in
                // What todo with Error?
            }
        }.store(in: &cancellables)
    }
}
