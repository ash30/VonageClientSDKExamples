//
//  Call.swift
//  VonageSDKClientVOIPExample
//
//  Created by Ashley Arthur on 01/02/2023.
//

import Foundation
import Combine
import VonageClientSDKVoice


// MARK: Call Model

/// Some aliases for convenience
///
typealias CallId = String
typealias LegId = String
let VonageLegStatusRinging = "ringing"
let VonageLegStatusAnswered = "answered"
let VonageLegStatusCompleted = "completed"
let LocalComplete = "LocalComplete"
let LocalReject = "LocalReject"

/// The Vonage Client offers the flexibility and freedom for customers to define their own CallModel
/// to suit their use case. In this sample application we will define a traditional PSTN one to one call model.
///
enum CallState {
    case ringing
    case answered
    case rejected
    case canceled
    case completed
    case unknown
}

enum OneToOneCall {
    case inbound(id:String, from:String, status:CallState)
    case outbound(id:String, to:String, status:CallState)
    
    init(call:Self, status: CallState){
        switch (call){
        case .inbound(let id, let from, _):
            self = .inbound(id:id, from: from, status:status )
        case .outbound(let id, let to, _):
            self = .outbound(id: id, to: to, status: status)
        }
    }
    var status: CallState {
        get {
            switch(self) {
            case .outbound(_,_,let status):
                return status
            case .inbound(_,_,let status):
                return status
            }
        }
    }
    
    var id: CallId {
        get {
            switch(self) {
            case .outbound(let callId,_,_):
                return callId
            case .inbound(let callId,_,_):
                return callId
            }
        }
    }
    
    /// The input to transition our state machine will be the callbacks provided by the ClientSDK Delegate
    ///
    func nextState(input:(call:CallId,leg:LegId,status:String)) -> CallState {
        switch(self){
        case .inbound:
            return nextStateInbound(input:input)
        case .outbound:
            return nextStateOutbound(input:input)
        }
    }
    
    private func nextStateOutbound(input:(call:CallId,leg:LegId,status:String)) -> CallState {
        switch (self.status) {
        case .ringing where (input.call != input.leg && input.status == VonageLegStatusAnswered):
            return .answered
        case .ringing where input.status == VonageLegStatusCompleted:
            return .rejected
        /// We introduce a specific local status so we can differentiate local cancel from remote reject
        case .ringing where input.status == LocalComplete:
            return .canceled
        case .answered where input.status == VonageLegStatusCompleted:
            return .completed
        default:
            return self.status
        }
    }
    
    private func nextStateInbound(input:(call:CallId,leg:LegId,status:String)) -> CallState {
        switch (self.status) {
        case .ringing where input.call == input.leg && input.status == VonageLegStatusAnswered:
            return .answered
        case .ringing where input.status == VonageLegStatusCompleted:
            return .canceled
        case .ringing where input.status == LocalReject:
            return .rejected
        case .answered where input.status == VonageLegStatusCompleted:
            return .completed
        default:
            return self.status
        }
    }
}


/// Convenience alias because we only support one type of call within this application
///
typealias Call = OneToOneCall


// MARK: Application Call State

/// We define the state of our application's call within a central state model
/// so the rest of the application can understand what to display
///
class ApplicationCallState: NSObject {
        
    private let vonage: VonageClientState
    private let appState: ApplicationState
    

    // MARK: INIT
    
    init(from appState:ApplicationState, and vonageClient:VGVoiceClient){
        self.vonage = VonageClientState(vonageClient: vonageClient)
        self.appState = appState
        super.init()
    }
    
    // MARK: Connectivity
        
    private lazy var vonageSessionId = appState
        .vonageServiceToken
        .flatMap { token in
            Future<String,Never>{ p in
                self.vonage.client.createSession(token, sessionId: nil) {err, sessionId in
                    // TODO: handle error
                    (err != nil) ? p(Result.success("")) : p(Result.success(sessionId!))
                }
            }
        }

    /// The public property for connectivty will be a simplified model based on callbacks from delegate
    /// ie. create session is the start of connectivty and then merge in the subsequent reconnection callbacks
    ///
    lazy var vonageConnectionState = self.vonage.vonageReconnections.prepend(.success(false))
        .combineLatest(vonageSessionId.eraseToAnyPublisher().catch { _ in Just("")
        })
        .map { (reconnects,sessionId) in
            if (sessionId == "")  {return Connection.disconnected(err: nil)}

            switch (reconnects){
            case let .success(flag) where flag == true:
                return Connection.reconnecting
            case let .success(flag) where flag == false:
                return Connection.connected
            case let .failure(err):
                return Connection.disconnected(err: err)
            default:
                return Connection.unknown
            }
        }
        .multicast(subject: CurrentValueSubject<Connection,Never>(.unknown))
        .autoconnect()
    
    //
//    lazy var isRegisteredForPush = appState.voipToken.combineLatest(appState.deviceToken)
//        .flatMap { (token1, token2) in
//            Future<String,Error>{ p in
//                self.vonage.registerDevicePushToken(token1, userNotificationToken: token2) { err, id in
//                    (err != nil) ? p(Result.failure(err!)) : p(Result.success(id!))
//                }
//            }
//        }
//        .map { _ in true }
//        .multicast(subject: CurrentValueSubject<Bool,Never>(false))

    
    // MARK: Calls
    
    /// Transform Vonage Calls into our call model
    ///
    lazy var outboundCalls = self.vonage.outboundVGCalls
        .compactMap { try? $0.get()}
        .map { (vgcall:VGVoiceCall) -> AnyPublisher<Call,Never> in
            let call = Call.outbound(id: vgcall.callId, to: "", status: .ringing)
            return self.vonage.vonageLegStatus
                .merge(with:self.vonage.localHangups.map { (call:$0.0, leg:$0.0, status:$0.1 == nil ? "localHangup" : "")} )
                .filter { $0.call == vgcall.callId }
                .scan(call) { call, update in
                    Call(call: call, status: call.nextState(input: update))
                }
                .eraseToAnyPublisher()
        }
    
    lazy var inboundCalls = self.vonage.vonageInvites
        .map { invite in
            let callId = invite.call
            let call = Call.inbound(id: callId, from: "", status: .ringing)
            
            return self.vonage.vonageCallHangup
                .merge(with: self.vonage.vonageLegStatus)
                .filter { $0.call == call.id}
                .scan(call) { call, legStatus in
                    Call(call: call, status: call.nextState(input: legStatus))
                }
                .eraseToAnyPublisher()
        }
    
    /// We keep a map of active calls by reducing over time the published calls
    /// This is a useful property for UI to understand IF we have any current calls at a given moment.
    ///
//    lazy var activeCalls = outboundCalls.eraseToAnyPublisher()
////        .merge(with: inboundCalls)
//        .flatMap { $0.map { $0 } }
//        .scan(Dictionary<CallId,Call>.init()){ all, call in
//            all.filter { elem in
//                elem.value.status != .completed
//            }
//            .merging([call.id:call], uniquingKeysWith: { (_, new) in new })
//        }
//        .multicast(subject: CurrentValueSubject([:]))
//        .autoconnect()


}

// MARK: Call Actions

/// A simple way for the view layer to update the application state is to notify via NSNotification

extension ApplicationCallState {
    static let CallStateStartOutboundCallNotification = NSNotification.Name("CallStateCreateCallNotification")
    
    static let CallStateLocalHangupNotification = NSNotification.Name("CallStateLocalHangupNotification")
    
    static let CallStateLocalRejectNotification = NSNotification.Name("CallStateLocalRejectNotification")

    static let CallStateLocalAnswerNotification = NSNotification.Name("CallStateLocalAnswerNotification")

}


// MARK: VonageClientDelegate+Publisher

typealias CallActionResult = (call:CallId, err:Error?)


