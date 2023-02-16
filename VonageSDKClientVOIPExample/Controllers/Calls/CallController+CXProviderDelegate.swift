//
//  CallController+CXProviderDelegate.swift
//  VonageSDKClientVOIPExample
//
//  Created by Ashley Arthur on 15/02/2023.
//

import Foundation
import CallKit
import VonageClientSDKVoice

extension CallController: CXProviderDelegate {
    
    func providerDidReset(_ provider: CXProvider) {
    }
    
    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        // We cheat a little bit with Outbound call starts -
        // 1. we create our vgcall first, so we can have the correct UUID
        // 2. We report to the cxcontroller afterwards
        // 3. here in the provider, we just call fulfill action right away
        action.fulfill()
        self.callProvider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date.now)
    }
    
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction){
        self.callkitAnswer.send(action)
    }
    
    func provider(_ provider: CXProvider, perform action: CXEndCallAction){
        self.callkitHangup.send(action)
    }
    
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession){
        VGVoiceClient.enableAudio(audioSession)
    }
    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession){
        VGVoiceClient.disableAudio(audioSession)
    }
}

extension CallController {
    
    func setupCallkit(_ state:ApplicationState) {
        
        // Pump our UI app actions through the cxcontroller
        // so we register them with callkit.
        ApplicationAction.publisher
            .sink { t in
                switch(t.action) {
                case .answerInboundCall(_, _):
                    self.cxController.requestTransaction(with: [CXAnswerCallAction(call: t.callid!)], completion: {_ in })
                case .hangupCall(_,_), .rejectInboundCall(_):
                    self.cxController.requestTransaction(with: [CXEndCallAction(call: t.callid!)], completion: {_ in})
                default:
                    return
                }
            }
            .store(in: &self.cancellables)
        
        
        // Report Incoming Calls
        state.newCalls
            .flatMap {
                $0.first()
            }
            .compactMap {
                if case let .inbound(id,from,.ringing) = $0 {
                    let update = CXCallUpdate()
                    update.localizedCallerName = from
                    return (id ,update)
                }; return nil
            }
            .sink { (id,update) in
            self.callProvider.reportNewIncomingCall(with: id, update: update) { err in
                // What todo with Error?
                // We should probably abort the call client side since the audio session will be foobar'd?
            }
        }.store(in: &cancellables)
        
        
        // Report Calls Hangups
        state.newCalls
            .flatMap { $0 }
            .sink { call in
                switch (call) {
                
                case .outbound(_,_,let status):
                    switch(status) {
                    case .ringing:
                        self.cxController.requestTransaction(with: [CXStartCallAction(call: call.id, handle: CXHandle(type: .generic, value: ""))], completion: { _ in })
                    case .answered:
                        self.callProvider.reportOutgoingCall(with: call.id, connectedAt: Date.now)
                    case .rejected:
                        self.callProvider.reportCall(with: call.id, endedAt: Date.now, reason: .remoteEnded)
                    default:
                        return
                    }
                case .inbound(_,_,let status):
                    switch (status) {
                    case .canceled:
                        self.callProvider.reportCall(with: call.id, endedAt: Date.now, reason: .unanswered)
                    default:
                        return
                    }
                }
            }
            .store(in: &cancellables)
        
        // Report the result of Actions
        self.callkitAnswer
            .flatMap { action in
                state.transactions.filter { $0.tid == action.uuid}.first().map { (action, $0.result) }
            }
            .sink { (action,result) in
                switch(result){
                case .failure:
                    action.fail()
                case .success:
                    action.fulfill()
                }
            }.store(in: &cancellables)
        
        self.callkitHangup
            .flatMap { action in
                state.transactions.filter { $0.tid == action.uuid}.first().map { (action, $0.result) }
            }
            .sink { (action,result) in
                switch(result){
                case .failure:
                    action.fail()
                case .success:
                    action.fulfill()
                }
            }.store(in: &cancellables)
    }
    
}
