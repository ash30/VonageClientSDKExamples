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

typealias CallId = String
typealias LegId = String

enum Connection {
    case unknown
    case connected
    case reconnecting
    case disconnected(err:Error?)
}

struct User {
    let info: UserDetails
    let token: String
}


enum CallState {
    case ringing
    case answered
    case rejected
    case canceled
    case completed
    case unknown
    
    static func fromString(_ s:String) -> CallState {
        switch s {
        case "ringing": return .ringing
        case "answered": return .answered
        case "completed": return .completed
        default: return .unknown
        }
    }
}

struct Call {
    let id: String
    let to: String
    let status: CallState
    let ref: VGVoiceCall
}

// MARK: Application Call State


class ApplicationCallState: NSObject,VGVoiceClientDelegate {
        
    private let vonage: VGVoiceClient
    private let appState: ApplicationState
    
    lazy var vonageSessionId = appState
        .vonageServiceToken
        .flatMap { token in
            Future<String,Never>{ p in
                self.vonage.createSession(token, sessionId: nil) {err, sessionId in
                    // TODO: handle error
                    (err != nil) ? p(Result.success("")) : p(Result.success(sessionId!))
                }
            }
        }
    
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
    
    lazy var isRegisteredForPush = appState.voipToken.combineLatest(appState.deviceToken)
        .flatMap { (token1, token2) in
            Future<String,Error>{ p in
                self.vonage.registerDevicePushToken(token1, userNotificationToken: token2) { err, id in
                    (err != nil) ? p(Result.failure(err!)) : p(Result.success(id!))
                }
            }
        }
        .map { _ in true }

    
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
    
    lazy var outbound = __outboundVGCalls
        .compactMap { try? $0.get()}
        .map { call in
            return self.vonageLegStatus
                .prepend((call.id, call.id, "ringing"))
                .filter { $0.call == call.id }
                .scan(call) { call, update in
                    if (call.status == .ringing){
                        if(update.status == "answered" && update.leg != call.id) {
                            return Call(
                                id: call.id,
                                to: call.to,
                                status: .answered,
                                ref: call.ref
                            )
                        }
                        if(update.status == "completed") {
                            return Call(
                                id: call.id,
                                to: call.to,
                                status: update.call == update.leg ? .canceled : .rejected ,
                                ref: call.ref
                            )
                        }
                    }
                    if (call.status == .answered){
                        if(update.status == "completed") {
                            return Call(
                                id: call.id,
                                to: call.to,
                                status: .completed,
                                ref: call.ref
                            )
                        }
                    }
                    return call
                }
                .eraseToAnyPublisher()

        }
    // TODO: Cancel
    
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

                                            
    
    init(from appState:ApplicationState, and vonageClient:VGVoiceClient){
        self.vonage = vonageClient
        self.appState = appState
        super.init()
        vonageClient.delegate = self
    }
    
    // MARK: VGVoiceClientDelegate Lifecycle
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

extension ApplicationCallState {
    static let CallStateStartOutboundCallNotification = NSNotification.Name("CallStateCreateCallNotification")
}
