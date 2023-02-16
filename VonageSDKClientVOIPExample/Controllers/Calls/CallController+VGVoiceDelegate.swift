//
//  Vonage+VGVoiceDelegate.swift
//  VonageSDKClientVOIPExample
//
//  Created by Ashley Arthur on 12/02/2023.
//

import Foundation
import VonageClientSDKVoice

typealias CallUpdate = (call:UUID, leg:UUID, status:String)

// Consts
let VonageLegStatusRinging = "ringing"
let VonageLegStatusAnswered = "answered"
let VonageLegStatusCompleted = "completed"
let LocalComplete = "LocalComplete"

extension CallController: VGVoiceClientDelegate {
    
    // MARK: VGVoiceClientDelegate Sessions
    
    /// The session is an object representing the connection with the vonage backend.
    /// We translate the session callbacks into a unified observable to represent a generalised concept of connection.
    ///
    func clientWillReconnect(_ client: VGBaseClient) {
        vonageWillReconnect.send(())
    }
    
    func clientDidReconnect(_ client: VGBaseClient) {
        vonageDidReconnect.send(())
    }
    
    func client(_ client: VGBaseClient, didReceiveSessionErrorWith reason: VGSessionErrorReason) {
        vonageSessionError.send(reason)
    }
    
    // MARK: VGVoiceClientDelegate Invites
    
    /// For inbound calls, the sdk will receive invite object from this callback
    ///
    func voiceClient(_ client: VGVoiceClient, didReceiveInviteForCall callId: String, with invite: VGVoiceInvite) {
        vonageInvites.send((call:UUID(uuidString: callId)!, invite:invite))
    }
    
    // MARK: VGVoiceClientDelegate LegStatus
    
    /// Leg Status update callbacks are how we understand what is happening to the individual connections
    /// within a single 'call'
    ///
    func voiceClient(_ client: VGVoiceClient, didReceiveLegStatusUpdateForCall callId: String, withLegId legId: String, andStatus status: String) {
        vonageLegStatus.send((UUID(uuidString: callId)!,UUID(uuidString: legId)!,status))
    }
    
    /// RTC hangup is special form of leg status update. Normally leg updates only fire for a leg once its joined a call.
    /// But for some cases in the classic 1 to 1 call model ie cancel, reject - the leg doesn't ever join the call.
    /// RTC Hangup will always fire for your leg when its terminated by the backend, so we can use it as 'completed' leg status event
    ///
    func voiceClient(_ client: VGVoiceClient, didReceiveHangupForCall callId: String, withLegId legId: String, andQuality callQuality: VGRTCQuality) {
        vonageCallHangup.send((call:UUID(uuidString: callId)!,leg:UUID(uuidString: legId)!, VonageLegStatusCompleted))
    }
    
}
