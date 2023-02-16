//
//  vonage.swift
//  VonageSDKClientVOIPExample
//
//  Created by Ashley Arthur on 12/02/2023.
//

import Foundation
import VonageClientSDKVoice
import Combine
import UIKit
import CallKit

typealias Session = String
typealias CallStream = AnyPublisher<Call,Never>

class CallController: NSObject {
    let client: VGVoiceClient
    var cancellables = Set<AnyCancellable>()
    
    // VGClient Delegate Methods as Subjects
    let vonageWillReconnect = PassthroughSubject<Void, Never>()
    let vonageDidReconnect = PassthroughSubject<Void, Never>()
    let vonageSessionError = PassthroughSubject<VGSessionErrorReason, Never>()
    let vonageInvites = PassthroughSubject<(call:UUID,invite:VGVoiceInvite), Never>()
    let vonageLegStatus = PassthroughSubject<CallUpdate, Never>()
    let vonageCallHangup = PassthroughSubject<CallUpdate, Never>()
        
    // Callkit
    lazy var callProvider = { () -> CXProvider in
        let provider = CXProvider(configuration: CXProviderConfiguration())
        provider.setDelegate(self, queue: nil)
        return provider
    }()
    lazy var cxController = CXCallController()
    
    // CXProvider Delegate Methods as Subjects
    let callkitAnswer = PassthroughSubject<CXAnswerCallAction,Never>()
    let callkitHangup = PassthroughSubject<CXEndCallAction,Never>()
    let callkitStartOutbound = PassthroughSubject<CXStartCallAction,Never>()
    
    var callErrors = PassthroughSubject<CallError,Never>()
    
    init(client:VGVoiceClient){
        self.client = client
        super.init()
        client.delegate = self
    }
}


extension CallController: ApplicationController {
    
    
    func bindToApplicationState(_ state: ApplicationState) {
        setupSession(state)
        setupCallHandlers(state)
        setupCallkit(state)
    }
    
    func setupSession(_ state:ApplicationState) {
        let session = state.$vonageToken
            .compactMap { token  in token }
            .first()
            .flatMap { token in
                Future<String?,Error> { p in
                    self.client.createSession(token) { err, session in
                        p(err != nil ? Result.failure(err!) : Result.success(session!))
                    }
                }
            }
            .catch { _ in Just(nil as String?) }

            .flatMap {
                Just($0)
                    .merge(with: self.vonageSessionError.map { _ in nil }.first())
                    .eraseToAnyPublisher()

                //                .merge(with: NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification).map { _ in nil }.first())
            }
        
        let activeSession = state.$user
            .compactMap { $0 }
            .map { _ in
                NotificationCenter.default
                    .publisher(for: UIApplication.willEnterForegroundNotification)
                    .map { _ in () }
                    .prepend( () )
                    .flatMap { _ in session.map {$0} }

            }
            .switchToLatest()


        // On session, upload push
        let pushRegistration = activeSession
            .combineLatest(
                state.$voipToken.compactMap { $0 },
                state.$deviceToken.compactMap { $0 }
            )
            .flatMap { values in
                Future { p in
                    self.client.registerDevicePushToken(values.1, userNotificationToken: values.2, isSandbox:true) {
                        err, device in
                        err != nil ? p(Result.failure(ApplicationErrors.PushNotRegistered)) : p (Result.success(true))
                    }
                }
                .catch { _ in Just(false) }
            }
            .first(where: {$0 == true})
            .prepend(false)
        
        // define cpaas connectivity
        let connection = activeSession
            .combineLatest(pushRegistration)
            .map { session, push in
                session.map { _ in
                    push == true ? Connection.connected : Connection.error(err: ApplicationErrors.PushNotRegistered)
                }
            }
            .map { connection in
                connection
                    .map { start in
                        Just(start)
                            .merge(with:
                                    self.vonageWillReconnect.map { _ in Connection.reconnecting }
                            )
                            .merge(with:
                                    self.vonageDidReconnect.map { _ in start }
                            )
                            .eraseToAnyPublisher()
                    }
                // should report error
                ?? Just(.disconnected(err: nil)).eraseToAnyPublisher()
            }
            .switchToLatest()

        
        connection.assign(to:&state.$connection)
        
    }
    
    func setupCallHandlers(_ state:ApplicationState) {
        
        // MARK: VGInvites
        let pushInvites = state.voipPush
            .map { payload in
                state.vonageToken.flatMap { token in
                    self.client.processCallInvitePushData(payload.dictionaryPayload, token: token)
                }
            }
            .compactMap { $0.map { invite in (id:UUID(uuidString: invite.callId)! ,invite:invite as VGVoiceInvite?)}}
            .share()
        
        let newInvites = vonageInvites
            .map { (id:$0.call, invite:$0.invite as VGVoiceInvite?)}
            .merge(with: pushInvites)
            .removeDuplicates(by: { a,b in a.id == b.id })        
        
        let activeInvites = newInvites
            .merge(with: self.vonageCallHangup.map { (id: $0.call, invite:nil) })
            .merge(with: self.vonageLegStatus.map { (id: $0.call, invite:nil) })
            .scan(Dictionary<UUID,VGVoiceInvite>()){ all, update in
                var new = all
                if (update.invite == nil ) { new.removeValue(forKey: update.0)  }
                else { new[update.0] = update.invite }
                return new
            }
            .multicast(subject:CurrentValueSubject<[UUID:VGVoiceInvite],Never>([:]))
            .autoconnect()
        
        
        // Answers
        let answer: (VGVoiceInvite) -> Future<VGVoiceCall,Error> = { invite in
            Future<VGVoiceCall,Error>{ p in
                invite.answer { err, call in
                    p(err != nil ? Result.failure(err!) : Result.success(call!))
                }
            }
        }
        
        let answeredInvites = activeInvites.map { invites in
            self.callkitAnswer
                .flatMap { action in
                    let stream = invites[action.callUUID].map { answer($0).asResult() }
                    ?? Just(
                        Result<VGVoiceCall,Error>.failure(ApplicationErrors.unknown)
                    ).eraseToAnyPublisher()
                    
                    return stream.map{ AppActionResult(tid: action.uuid, callid: action.callUUID, result: $0) }
                }
        }
            .switchToLatest()
            .share()
        
        // Rejects
        // Callkit uses the same CXAction for reject + hangup
        
        let reject: (VGVoiceInvite) -> Future<Void,Error> = { invite in
            Future<Void,Error>{ p in
                invite.reject { err in
                    p(err != nil ? Result.failure(err!) : Result.success(()))
                }
            }
        }
        
        let rejectedInvites = activeInvites.map { invites in
            self.callkitHangup.flatMap{ action in
                let stream = invites[action.callUUID].map { reject($0).asResult().eraseToAnyPublisher() }
                ?? Empty().eraseToAnyPublisher()
                return stream.map { AppActionResult(tid: action.uuid, callid: action.callUUID, result: $0.map {_ in action.callUUID } ) }
            }
        }
            .switchToLatest()
            .share()
        
        // MARK: VGCalls
        
        let outboundCalls = ApplicationAction.publisher
            .compactMap { if case let .newOutboundCall(context) = $0.action {return ($0.tid,context)}; return nil}
            .flatMap { (t:(UUID, [String:Any])) in
                Future<VGVoiceCall,Error>{ p in
                    self.client.serverCall(t.1) { err, call in
                        (err != nil) ? p(Result.failure(err!)) : p(Result.success(call!))
                    }
                }
                .asResult()
                .map { AppActionResult(tid: t.0, callid: nil, result: $0) }
            }
            .share()
            .eraseToAnyPublisher()
        
        let allNewCalls = answeredInvites
            .merge(with:outboundCalls)
            .compactMap { try? $0.result.get() }
            .map { (id:UUID(uuidString: $0.callId)!, call:$0 as VGVoiceCall?)}
        
        let currentActiveCalls = allNewCalls
            .merge(with: self.vonageCallHangup.map {(id:$0.call, call:nil as VGVoiceCall?)})
            .scan(Dictionary<UUID,VGVoiceCall>()) { all, update  in
                var new = all
                if (update.1 == nil ) { new.removeValue(forKey: update.id)  }
                else { new[update.id] = update.1 }
                return new
            }
            .multicast(subject:CurrentValueSubject<[UUID:VGVoiceCall],Never>([:]))
            .autoconnect()
        

        // MARK: HANGUP
        
        let hangup: (VGVoiceCall) -> Future<Void,Error> = { call in
            Future<Void,Error>{ p in
                call.hangup { err in
                    p(err == nil ? Result.success(()) : Result.failure(err!))
                }
            }
        }
        
        let finishedCalls = currentActiveCalls.map { calls in
            self.callkitHangup
                .flatMap{ action in
                    let stream = calls[action.callUUID].map { hangup($0).asResult().eraseToAnyPublisher() }
                    ?? Empty().eraseToAnyPublisher()
                    return stream.map { AppActionResult(tid: action.uuid, callid: action.callUUID, result: $0.map {_ in action.callUUID } ) }
                }
        }
            .switchToLatest()
            .share()

        
        let transactions = rejectedInvites.map { $0.asAnyResult() }
            .merge(with: outboundCalls.map { $0.asAnyResult() })
            .merge(with: answeredInvites.map { $0.asAnyResult() })
            .merge(with: finishedCalls.map { $0.asAnyResult() })
            .share()
       
        
        transactions.sink {
            state.transactions.send($0)
        }.store(in: &cancellables)
        
        // MARK: CAll Streams
        
        let outboundStreams = outboundCalls
            .compactMap { try? $0.result.get()}
            .map { (vgcall:VGVoiceCall) -> AnyPublisher<Call,Never> in
                let call = Call.outbound(id: UUID(uuidString: vgcall.callId)!, to: "", status: .ringing)
                return self.vonageLegStatus
                    .merge(with: finishedCalls
                        .compactMap { try? $0.result.get() }
                        .map {
                            (call:$0, leg:$0, status:LocalComplete)
                        }
                    )
                    .filter { $0.call == UUID(uuidString: vgcall.callId)! }
                    .scan(call) { call, update in
                        Call(call: call, status: call.nextState(input: update))
                    }
                    .removeDuplicates(by: {a,b in a.status == b.status })
//                    .prepend(call)
                    .share()
                    .eraseToAnyPublisher()
            }
        
        let inboundStreams = newInvites
            .map { new in
                let callId = new.invite!.callId
                let call = Call.inbound(id: UUID(uuidString: callId)!, from: "", status: .ringing)
                
                return self.vonageCallHangup
                    .merge(with: self.vonageLegStatus)
                    .filter { $0.call == call.id}
                    .scan(call) { call, legStatus in
                        Call(call: call, status: call.nextState(input: legStatus))
                    }
                    .prepend(call)
                    .eraseToAnyPublisher()
            }
        
        // Final public Call Observable
        let callStreams = inboundStreams.merge(with: outboundStreams)
        
        callStreams
            .sink { state.newCalls.send($0) }
            .store(in: &cancellables)
        
    }
}
