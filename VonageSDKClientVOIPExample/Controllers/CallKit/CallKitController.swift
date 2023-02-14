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
        
        let newVoipCalls = state.voipPush
            .map { payload in
                state.vonageToken.flatMap { token in
                    self.client.processCallInvitePushData(payload.dictionaryPayload, token: token)
                        .map { invite in
                            let update = CXCallUpdate()
                            update.localizedCallerName = invite.from
                            let uuid = invite.callUUID ?? UUID()
                            return (uuid,update)
                        }
                   
                }
                ?? (UUID(),CXCallUpdate())
            }
        
        newVoipCalls.sink { update in
            self.callProvider.reportNewIncomingCall(with: update.0, update: update.1) { err in
                // What todo with Error?
            }
        }.store(in: &cancellables)
    }
}
