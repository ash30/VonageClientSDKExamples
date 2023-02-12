//
//  Call.swift
//  VonageSDKClientVOIPExample
//
//  Created by Ashley Arthur on 01/02/2023.
//

import Foundation
import Combine
import VonageClientSDKVoice
import CallKit


// MARK: Call Model

/// Some aliases for convenience
///
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
    case inbound(id:UUID, from:String, status:CallState)
    case outbound(id:UUID, to:String, status:CallState)
    
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
    
    var id: UUID {
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
    func nextState(input:(call:UUID,leg:UUID,status:String)) -> CallState {
        switch(self){
        case .inbound:
            return nextStateInbound(input:input)
        case .outbound:
            return nextStateOutbound(input:input)
        }
    }
    
    private func nextStateOutbound(input:(call:UUID,leg:UUID,status:String)) -> CallState {
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
    
    private func nextStateInbound(input:(call:UUID,leg:UUID,status:String)) -> CallState {
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
    
    // private deps
    lazy var callProvider = { () -> CXProvider in
        let provider = CXProvider(configuration: CXProviderConfiguration())
        provider.setDelegate(self, queue: nil)
        return provider
    }()
    
    lazy var callController = CXCallController()
    
    private let vonage: VonageClientState
    private let appState: ApplicationState
    
    var cancellables = Set<AnyCancellable>()

    // MARK: INIT
    
    init(from appState:ApplicationState, and cpaasState:VonageClientState){
        self.vonage = cpaasState
        self.appState = appState
        super.init()
                
        // Make the following streams hot
        connectivity.sink{ _ in }.store(in: &cancellables)
        
        // Side effects
        // Keep Callkit in sync with whats going on
        newCXCallUpdates.sink { update in
            self.callProvider.reportNewIncomingCall(with: update.0, update: update.1) { err in
                // What todo with Error??
            }
        }
        .store(in: &self.cancellables)
        
        // Need to deduplicate ...
        localHangups.sink{
            guard $0.err == nil else {
                return
            }
            let callId = $0.call
            let action = CXEndCallAction(call:callId)
            self.callController.request(
                CXTransaction(action: action),
                completion: { _ in
                    NSLog("here")
                }
            )
        }.store(in: &cancellables)

    }
    
    /// We combine the creation of the session AND the other callbacks for reconnections to provide a unified
    /// connectivity value for the UI layer
    ///
    lazy var connectivity = vonage.session
        .combineLatest(self.vonage.pushRegistration)
        .map { session, p in
            session.map { _ in p == true ? Connection.connected : Connection.error(err: ApplicationErrors.PushNotRegistered)
            }
        }
        .map { connection in
            connection
                .map { start in
                    Just(start)
                        .merge(with:
                                self.vonage.vonageWillReconnect.map { _ in Connection.reconnecting }
                        )
                        .merge(with:
                                self.vonage.vonagedidReconnect.map { _ in start }
                        )
                        .eraseToAnyPublisher()
                }
                ?? Just(.disconnected(err: nil)).eraseToAnyPublisher()
        }
        .switchToLatest()
        .multicast(subject: CurrentValueSubject<Connection,Never>(.disconnected(err: nil)))
        .autoconnect()
    
    
    private lazy var newCXCallUpdates = self.appState.voipPush
        .flatMap { payload in
            self.appState.vonageServiceToken.map { token in
                self.vonage.client
                    .processCallInvitePushData(payload.dictionaryPayload, token: token)
                    .map { invite in
                        let update = CXCallUpdate()
                        update.localizedCallerName = invite.from
                        let uuid = invite.callUUID ?? UUID()
                        return (uuid,update)
                    }
                ?? (UUID(),CXCallUpdate())
            }.catch { _ in Just((UUID(),CXCallUpdate()))}
        }
    
    // MARK: Calls
    
    /// Transform Vonage Calls into our call model
    ///
    lazy var outboundCalls = self.vonage.outboundVGCalls
        .compactMap { try? $0.get()}
        .map { (vgcall:VGVoiceCall) -> AnyPublisher<Call,Never> in
            let call = Call.outbound(id: UUID(uuidString: vgcall.callId)!, to: "", status: .ringing)
            return self.vonage.vonageLegStatus
                .merge(with:self.localHangups.map { (call:$0.0, leg:$0.0, status:$0.1 == nil ? "localHangup" : "")} )
                .filter { $0.call == UUID(uuidString: vgcall.callId)! }
                .scan(call) { call, update in
                    Call(call: call, status: call.nextState(input: update))
                }
                .prepend(call)
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
                .prepend(call)
                .eraseToAnyPublisher()
        }
    
    /// We keep a map of active calls by reducing over time the published calls
    /// This is a useful property for UI to understand IF we have any current calls at a given moment.
    ///
//    lazy var activeCalls = outboundCalls.eraseToA nyPublisher()
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


    // MARK: Events
    
    
    lazy var localHangups = NotificationCenter.default.publisher(for: ApplicationCallState.CallStateLocalHangupNotification)
        .compactMap { n  in n.userInfo!["callId"] as? UUID}
        .flatMap{ callId  in
            self.vonage.activeVGCalls.first().flatMap { calls in 
                calls[callId].map { call in
                    Future<CallActionResult,Never>{ p in
                        call.hangup { err in
                            p(Result.success((call:callId, err:err)))
                        }
                    }
                    .eraseToAnyPublisher()
                }
                ?? Just((call:callId,err:ApplicationErrors.unknown)).eraseToAnyPublisher()
            }
        }
        .eraseToAnyPublisher()
        .share()

    
}

// MARK: Call Actions

/// A simple way for the view layer to update the application state is to notify via NSNotification

extension ApplicationCallState {
    static let CallStateStartOutboundCallNotification = NSNotification.Name("CallStateCreateCallNotification")
    
    static let CallStateLocalHangupNotification = NSNotification.Name("CallStateLocalHangupNotification")
    
    static let CallStateLocalRejectNotification = NSNotification.Name("CallStateLocalRejectNotification")

    static let CallStateLocalAnswerNotification = NSNotification.Name("CallStateLocalAnswerNotification")

    static let CallStateConnectionStart = NSNotification.Name("CallStateConnectionStart")
}


// MARK: VonageClientDelegate+Publisher

typealias CallActionResult = (call:UUID, err:Error?)


// MARK: CXProviderDelegate

extension ApplicationCallState: CXProviderDelegate {
    
    func providerDidReset(_ provider: CXProvider) {
    }
    
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction){
        self.vonage.answeredInvites
            .compactMap { try? $0.get() }
            .map { UUID(uuidString: $0.callId)! }
            .filter { $0 == action.callUUID }
            .first()
            .sink { _ in
                action.fulfill()
            }.store(in: &cancellables)
        
        NotificationCenter.default.post(name: ApplicationCallState.CallStateLocalAnswerNotification, object:nil, userInfo: ["callId": action.callUUID ])
        
    }
    
    func provider(_ provider: CXProvider, perform action: CXEndCallAction){
        NotificationCenter.default.post(name: ApplicationCallState.CallStateLocalHangupNotification, object:nil, userInfo: ["callId": action.callUUID ])
    }
    
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession){
        VGVoiceClient.enableAudio(audioSession)
    }
    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession){
        VGVoiceClient.disableAudio(audioSession)
    }
}
