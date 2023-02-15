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
    private var cancellables = Set<AnyCancellable>()
    
    // VGClient Delegate Methods as Subjects
    let vonageWillReconnect = PassthroughSubject<Void, Never>()
    let vonageDidReconnect = PassthroughSubject<Void, Never>()
    let vonageSessionError = PassthroughSubject<VGSessionErrorReason, Never>()
    let vonageInvites = PassthroughSubject<(call:UUID,invite:VGVoiceInvite), Never>()
    let vonageLegStatus = PassthroughSubject<CallUpdate, Never>()
    let vonageCallHangup = PassthroughSubject<CallUpdate, Never>()
        
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
         
        let answeredInvites = activeInvites.map { invites in
            ApplicationAction.publisher
                .compactMap { if case let .answerInboundCall(callId,_) = $0 { return callId }; return nil }
                .flatMap { callId in
                    invites[callId].map { invite in
                        Future<VGVoiceCall,CallError>{ p in
                            invite.answer { err, call in
                                p(err != nil ? Result.failure(CallError(id: callId, err: err)) : Result.success(call!))
                            }
                        }
                        .asResult()
                        .eraseToAnyPublisher()
                    } ?? Just(
                        Result<VGVoiceCall,CallError>.failure(
                            CallError(id: callId, err:ApplicationErrors.unknown)
                        )
                    ).eraseToAnyPublisher()
                }
        }
            .switchToLatest()
            .share()
        
        let rejectedInvites = activeInvites.map { invites in
            ApplicationAction.publisher
                .compactMap { if case let .rejectInboundCall(callId) = $0 { return callId }; return nil }
                .flatMap { callId in
                    invites[callId].map { invite in
                        Future<Void,CallError>{ p in
                            invite.reject { err in
                                p(err != nil ? Result.failure(CallError(id: callId, err: err)) : Result.success(()))
                            }
                        }
                        .asResult()
                    } ?? Just(
                        Result<Void,CallError>.failure(
                            CallError(id: callId, err:ApplicationErrors.unknown)
                        )
                    ).eraseToAnyPublisher()
                }.eraseToAnyPublisher()
        }
            .switchToLatest()
            .share()
        
        // MARK: VGCalls
        
        let outboundCalls = ApplicationAction.publisher
            .compactMap { if case let .newOutboundCall(context) = $0 {return context}; return nil}
            .flatMap { context in
                Future{ p in
                    self.client.serverCall(context) { err, call in
                        (err != nil) ? p(Result.failure(err!)) : p(Result.success(call!))
                    }
                }
                .mapError { CallError(id: nil, err: $0) }
                .asResult()
            }
            .share()
            .eraseToAnyPublisher()
        
        
        // MARK: APPLICATION Calls
        
        let allNewCalls = answeredInvites
            .merge(with:outboundCalls)
            .compactMap { try? $0.get() }
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
        
        let finishedCalls = currentActiveCalls.map { calls in
            ApplicationAction.publisher
                .compactMap { if case let .hangupCall(callId,_) = $0 { return callId }; return nil }
                .flatMap{ callId  in
                    calls[callId].map { call in
                        Future<UUID,CallError>{ p in
                            call.hangup { err in
                                p(err == nil ? Result.success(callId) : Result.failure(CallError(id: callId, err: err)))
                            }
                        }
                        .asResult()
                    }
                    ?? Just(Result.failure(CallError(id: callId, err: nil))).eraseToAnyPublisher()
                    
                }
        }
            .switchToLatest()
            .share()
        
        // We need to keep Callkit in sync with our Call Controller
        // here we report the result of hangups initiated by callkit UI back to originating CXAction
        ApplicationAction.publisher
            .compactMap { if case let .hangupCall(_,cxaction) = $0 { return cxaction }; return nil }
            .flatMap { (action:CXEndCallAction) in
                finishedCalls
                    .filter { result in
                        switch(result){
                        case .success(let uuid): return uuid == action.callUUID
                        case.failure(let err): return (err.id ?? UUID()) == action.callUUID
                        }
                    }
                    .map {
                        (action, $0.map{ _ in Void()}.mapError{$0 as Error})
                    }
                    .merge(with: Just((action, Result<Void,Error>.failure(ApplicationErrors.unknown))).delay(for: 10.0, scheduler: RunLoop.main) )
                    .first()
            }
            .sink { (action,result) in
                switch (result) {
                case .success:
                    action.fulfill()
                case .failure:
                    action.fail()
                }
            }
            .store(in: &cancellables)
        
        // Same for answers
        ApplicationAction.publisher
            .compactMap { if case let .answerInboundCall(_,cxaction) = $0 { return cxaction }; return nil }
            .flatMap { (action:CXAnswerCallAction) in
                answeredInvites
                    .filter { result in
                        switch(result){
                        case .success(let call): return (UUID(uuidString: call.callId)!) == action.callUUID
                        case.failure(let err): return (err.id ?? UUID()) == action.callUUID
                        }
                    }
                    .map {
                        (action, $0.map{ _ in Void()}.mapError{$0 as Error})
                    }
                    .merge(with: Just((action, Result<Void,Error>.failure(ApplicationErrors.unknown))).delay(for: 10.0, scheduler: RunLoop.main) )
                    .first()
            }
            .sink { (action,result) in
                switch (result) {
                case .success:
                    action.fulfill()
                case .failure:
                    action.fail()
                }
            }
            .store(in: &cancellables)
        
        let errors = rejectedInvites
            .merge(with: outboundCalls.map { $0.map {_ in ()} })
            .merge(with: answeredInvites.map { $0.map {_ in ()} })
            .merge(with: finishedCalls.map { $0.map {_ in ()} })
            .compactMap { if case let .failure(err) = $0 { return err }; return nil}
        
        errors
            .sink { self.callErrors.send($0)}
            .store(in: &self.cancellables)
        
        
        // MARK: CAll Streams
        
        let outboundStreams = outboundCalls
            .compactMap { try? $0.get()}
            .map { (vgcall:VGVoiceCall) -> AnyPublisher<Call,Never> in
                let call = Call.outbound(id: UUID(uuidString: vgcall.callId)!, to: "", status: .ringing)
                return self.vonageLegStatus
                    .merge(with: finishedCalls
                        .compactMap { try? $0.get() }
                        .map {
                            (call:$0, leg:$0, status:LocalComplete)
                        }
                    )
                    .filter { $0.call == UUID(uuidString: vgcall.callId)! }
                    .scan(call) { call, update in
                        Call(call: call, status: call.nextState(input: update))
                    }
                    .prepend(call)
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
        
        // Final Public Call Observable
        let callStreams = inboundStreams.merge(with: outboundStreams)
        
        callStreams
            .sink { state.newCalls.send($0) }
            .store(in: &cancellables)
        
    }
}
