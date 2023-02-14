//
//  CallKitController+CALL.swift
//  VonageSDKClientVOIPExample
//
//  Created by Ashley Arthur on 14/02/2023.
//

import Foundation
import CallKit
import VonageClientSDKVoice

extension CallKitController: CXProviderDelegate {
    
    func providerDidReset(_ provider: CXProvider) {
    }
    
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction){
        ApplicationAction.post(.answerInboundCall(id: action.callUUID))
        action.fulfill()
    }
    
    func provider(_ provider: CXProvider, perform action: CXEndCallAction){
        ApplicationAction.post(.hangupCall(id: action.callUUID))
        action.fulfill()
    }
    
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession){
        VGVoiceClient.enableAudio(audioSession)
    }
    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession){
        VGVoiceClient.disableAudio(audioSession)
    }
}
