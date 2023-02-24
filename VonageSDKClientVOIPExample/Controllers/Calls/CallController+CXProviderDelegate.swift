//
//  CallController+CXProviderDelegate.swift
//  VonageSDKClientVOIPExample
//
//  Created by Ashley Arthur on 15/02/2023.
//

import Foundation
import CallKit
import VonageClientSDKVoice
import AudioToolbox

extension CallController: CXProviderDelegate {
    
    func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(AVAudioSession.Category.playAndRecord, mode: AVAudioSession.Mode.voiceChat, options: .allowBluetooth)
        } catch {
            print(error)
        }
    }
    
    
    func providerDidReset(_ provider: CXProvider) {
    }
    
    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        // We cheat a little bit with Outbound call starts -
        // 1. we create our vgcall first, so we can have the correct UUID
        // 2. We report to the cxcontroller afterwards
        // 3. here in the provider, we just call fulfill action right away
        configureAudioSession()
        action.fulfill()
        self.callProvider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date.now)
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction){
        configureAudioSession()
        
//        _semaphore = dispatch_semaphore_create(0);
        self.callkitAnswer.send(action)
        action.fulfill()

    }
    
    func provider(_ provider: CXProvider, perform action: CXEndCallAction){
        self.callkitHangup.send(action)
    }
    
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession){
        
        // When the mic and speakers are ready, enable audio within clientsdk
//        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
//            .map { _ in
//                AVAudioSession.sharedInstance().currentRoute.outputs
//            }
//            .filter { !(($0.filter { $0.portType == .builtInReceiver }).isEmpty) }
//            .first()
//            .sink { _ in
//                print(AVAudioSession.sharedInstance().currentRoute.outputs, "FOO:\(#function)")
//                VGVoiceClient.enableAudio(audioSession)
//            }.store(in: &self.cancellables)
            print(AVAudioSession.sharedInstance().currentRoute.outputs, "FOO:\(#function)")
        VGVoiceClient.enableAudio(audioSession)

        
        
    }
    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession){
        print(AVAudioSession.sharedInstance().currentRoute.outputs, "FOO:\(#function)")
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
                    update.localizedCallerName = "foo"
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
                    case .completed(remote: true):
                        self.callProvider.reportCall(with: call.id, endedAt: Date.now, reason: .remoteEnded)
                    default:
                        return
                    }
                case .inbound(_,_,let status):
                    switch (status) {
                    case .canceled:
                        self.callProvider.reportCall(with: call.id, endedAt: Date.now, reason: .unanswered)
                    case .completed(remote: true):
                        self.callProvider.reportCall(with: call.id, endedAt: Date.now, reason: .remoteEnded)
                    default:
                        return
                    }
                }
            }
            .store(in: &cancellables)
        
        // Report the result of Actions
//        self.callkitAnswer
//            .flatMap { action in
//                state.transactions.filter { $0.tid == action.uuid}.first().map { (action, $0.result) }
//            }
//            .print("FOO:answer action")
//
////            .receive(on: RunLoop.main)
//            .sink { (action,result) in
//                switch(result){
//                case .failure:
//                    action.fail()
//                case .success:
//                    action.fulfill()
//                }
//            }.store(in: &cancellables)
        
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
