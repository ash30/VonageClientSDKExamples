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

/// The Vonage Client offers the flexibility and freedom for customers to define their own CallModel
/// to suit their use case. In this sample application we will define a traditional PSTN like model.
///
enum OneToOneCallState {
    case ringing
    case answered
    case rejected
    case canceled
    case completed
    case unknown
    
    /// The input to transition our state machine will be the callbacks provided by the ClientSDK Delegate
    ///
    func nextState(input:(call:CallId,leg:LegId,status:String)) -> Self {
        switch self {
        case .ringing where input.call != input.leg:
            return .answered
        case .ringing where input.status == VonageLegStatusCompleted:
            return .rejected
        /// We introduce a specific local status so we can differentiate local cancel from remote reject
        case .ringing where input.status == LocalComplete:
            return .canceled
        case .answered where input.status == VonageLegStatusCompleted:
            return .completed
        default:
            return self
        }
    }
}

enum CallDetails {
    case inbound(from:String)
    case outbound(to:String, context:[String:any Hashable])
}

struct BaseCall<T> {
    let id: String
    let to: String
    let status: T
    let ref: VGVoiceCall
    
    init(id:String, to:String, status:T, ref:VGVoiceCall) {
        self.id = id
        self.to = to
        self.status = status
        self.ref = ref
    }
    
    init(call:Self, status:T){
        self.id = call.id
        self.to = call.to
        self.status = status
        self.ref = call.ref
    }
}

/// Convenience alias because we only support one type of call within this application
///
typealias Call = BaseCall<OneToOneCallState>



// MARK: Application Call State

/// We define the state of our application's call within a central state model
/// so the rest of the application can understand what to display
///
class ApplicationCallState: NSObject,VGVoiceClientDelegate {
        
    private let vonage: VGVoiceClient
    private let appState: ApplicationState
    
    // MARK: Session
    
    /// Our Vonage Session is based on transforming the application logged in user
    /// this way we couple their lifetimes .e.g When logged out, we should disconnect from vonage backend
    ///
    private lazy var vonageSessionId = appState
        .vonageServiceToken
        .flatMap { token in
            Future<String,Never>{ p in
                self.vonage.createSession(token, sessionId: nil) {err, sessionId in
                    // TODO: handle error
                    (err != nil) ? p(Result.success("")) : p(Result.success(sessionId!))
                }
            }
        }
    
    /// The public property for connectivty will be a simplified model based on callbacks from delegate
    /// ie. create session is the start of connectivty and then merge in the subsequent reconnection callbacks
    ///
    lazy var vonageConnectionState = vonageReconnections.prepend(.success(false))
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

    /// We publish our hangups so we can utilise it as apart of the call state machine
    ///
    lazy var localHangups = NotificationCenter.default.publisher(for: ApplicationCallState.CallStateLocalHangupNotification)
        .map { n  in n.userInfo?["call"] as? VGVoiceCall}
        .compactMap{ $0 }
        .flatMap { (call) in
            Future<Error?,Never>{ p in
                call.hangup { err in
                    p(Result.success(err))
                }
            }
            .map { err in
                (call.callId, err)
            }
        }
        .share()
    
    
    /// Internally we transform actions to make outbound calls into a vonage call object
    /// Note: Generally all streams with side effects are multicast to only make the request once regardless of subscriber count
    ///
    private lazy var __outboundVGCalls =  NotificationCenter.default.publisher(for: ApplicationCallState.CallStateStartOutboundCallNotification)
        .map { n  in n.userInfo}
        .flatMap { context in
            Future{ p in
                self.vonage.serverCall(context) { err, call in
                    (err != nil) ? p(Result.failure(err!)) : p(Result.success(call!))
                }
            }
            .map { vgcall in
                Result<Call,Error>.success(
                    Call(
                        id: vgcall.callId,
                        to: (context?["to"] as? String) ?? "",
                        status: .ringing,
                        ref: vgcall
                    ))
            }
            .catch { err in
                Just(Result<Call,Error>.failure(err))
            }
        }
        .multicast(subject: PassthroughSubject())
        .autoconnect()
        .eraseToAnyPublisher()
    
//    lazy var outboundErrors = __outboundVGCalls
//        .map { result -> Error? in result.map {_ in nil}.catch{ $0 } }
//        .compactMap { $0 }
    
    
    /// Transform Vonage Calls into our call model
    ///
    lazy var outbound = __outboundVGCalls
        .compactMap { try? $0.get()}
        .map { call in
            return self.vonageLegStatus
                .prepend((call.id, call.id, "ringing"))
                .eraseToAnyPublisher()
                .merge(with:self.localHangups.map { (call:$0.0, leg:$0.0, status:$0.1 == nil ? "localHangup" : "")} )
                .filter { $0.call == call.id }
                .scan(call) { call, update in
                    Call(call: call, status: call.status.nextState(input: update))
                }
                .eraseToAnyPublisher()

        }
    
    /// We keep a map of active calls by reducing over time the published calls
    /// This is a useful property for UI to understand IF we have any current calls at a given moment.
    ///
    lazy var activeCalls = outbound
        .flatMap { $0.map { $0 } }
        .scan(Dictionary<CallId,Call>.init()){ all, call in
            all.filter { elem in
                elem.value.status != .completed
            }
            .merging([call.id:call], uniquingKeysWith: { (_, new) in new })
        }
        .multicast(subject: CurrentValueSubject([:]))
        .autoconnect()

       
    
    // MARK: INIT
    
    init(from appState:ApplicationState, and vonageClient:VGVoiceClient){
        self.vonage = vonageClient
        self.appState = appState
        super.init()
        vonageClient.delegate = self
    }
    
    // MARK: VGVoiceClientDelegate Lifecycle
    
    /// Our integration with the vonage client is mainly to transform the client delegate into observables
    /// for down stream subscribers.
    ///
    let vonageReconnections = PassthroughSubject<Result<Bool,Error>, Never>()
    func clientWillReconnect(_ client: VGBaseClient) {
        vonageReconnections.send(Result.success(true))
    }
    func clientDidReconnect(_ client: VGBaseClient) {
        vonageReconnections.send(Result.success(false))
    }
    func client(_ client: VGBaseClient, didReceiveSessionErrorWith reason: VGSessionErrorReason) {
        vonageReconnections.send(Result.failure(reason))
    }
    
    func voiceClient(_ client: VGVoiceClient, didReceiveInviteForCall callId: String, with invite: VGVoiceInvite) {
    }
    
    let vonageCallHangup = PassthroughSubject<(String,Bool), Never>()
    func voiceClient(_ client: VGVoiceClient, didReceiveHangupForCall callId: String, withLegId legId: String, andQuality callQuality: VGRTCQuality) {
        vonageCallHangup.send((callId,callId == legId))
    }
    
    let vonageLegStatus = PassthroughSubject<(call:CallId,leg:LegId,status:String), Never>()
    func voiceClient(_ client: VGVoiceClient, didReceiveLegStatusUpdateForCall callId: String, withLegId legId: String, andStatus status: String) {
        vonageLegStatus.send((callId,legId,status))
    }
}

// MARK: Call Actions

/// A simple way for the view layer to update the application state is to notify via NSNotification

extension ApplicationCallState {
    static let CallStateStartOutboundCallNotification = NSNotification.Name("CallStateCreateCallNotification")
    
    static let CallStateLocalHangupNotification = NSNotification.Name("CallStateLocalHangupNotification")
}
