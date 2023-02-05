//
//  Vonage.swift
//  VonageSDKClientVOIPExample
//
//  Created by Ashley Arthur on 05/02/2023.
//

import Foundation
import VonageClientSDKVoice
import Combine


class VonageClientState: NSObject, VGVoiceClientDelegate {
    
    let client: VGVoiceClient
    private var cancellables = Set<AnyCancellable>()
    
    init(vonageClient:VGVoiceClient){
        self.client = vonageClient
        super.init()
        vonageClient.delegate = self
        
        self.activeInvites.sink(receiveValue: {_ in}).store(in: &cancellables)
        self.activeVGCalls.sink(receiveValue: {_ in}).store(in: &cancellables)
    }
    
    /// # Basic Publishers
    /// We are going to convert the stadard delegate interface of the client sdk into a series of combine publishers.
    /// The sdk is low level and flexible enough  to accomodate any programming style, we could happily choose a more
    /// traditional OOP approach, but the observables/publishers of combine will provide strong code locality
    /// when defining logic and hopefully help
    
    // MARK: VGVoiceClientDelegate Sessions
    
    /// The session is an object representing the connection with the vonage backend.
    /// We translate the session callbacks into a unified observable to represent a generalised concept of connection.
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
    
    // MARK: VGVoiceClientDelegate Invites
    
    /// For inbound calls, the sdk will receive invite object from this callback
    ///
    let vonageInvites = PassthroughSubject<(call:CallId,invite:VGVoiceInvite), Never>()
    func voiceClient(_ client: VGVoiceClient, didReceiveInviteForCall callId: String, with invite: VGVoiceInvite) {
        vonageInvites.send((call:callId, invite:invite))
    }
    
    // MARK: VGVoiceClientDelegate LegStatus

    /// Leg Status update callbacks are how we understand what is happening to the individual connections
    /// within a single 'call'
    ///
    let vonageLegStatus = PassthroughSubject<(call:CallId,leg:LegId,status:String), Never>()
    func voiceClient(_ client: VGVoiceClient, didReceiveLegStatusUpdateForCall callId: String, withLegId legId: String, andStatus status: String) {
        vonageLegStatus.send((callId,legId,status))
    }
    
    /// RTC hangup is special form of leg status update. Normally leg updates only fire for a leg once its joined a call.
    /// But for some cases in the classic 1 to 1 call model ie cancel, reject - the leg doesn't ever join the call.
    /// RTC Hangup will always fire for your leg when its terminated by the backend, so we can use it as 'completed' leg status event
    ///
    let vonageCallHangup = PassthroughSubject<(call:CallId,leg:LegId,status:String), Never>()
    func voiceClient(_ client: VGVoiceClient, didReceiveHangupForCall callId: String, withLegId legId: String, andQuality callQuality: VGRTCQuality) {
        vonageCallHangup.send((call:callId,leg:legId, VonageLegStatusCompleted))
    }
    
    
    /// # High level Publishers
    /// Here the aim is to transform the basic publisher of the client delegate into higher level concepts
    /// for our business logic to utilise.
    ///
    ///
    
    // MARK: Call Helpers

    lazy var outboundVGCalls =  NotificationCenter.default.publisher(for: ApplicationCallState.CallStateStartOutboundCallNotification)
        .map { n  in n.userInfo}
        .flatMap { context in
            Future{ p in
                self.client.serverCall(context) { err, call in
                    (err != nil) ? p(Result.failure(err!)) : p(Result.success(call!))
                }
            }
            .map {
                Result<VGVoiceCall,Error>.success($0)
            }
            .catch { err in
                Just(Result<VGVoiceCall,Error>.failure(err))
            }
        }
        .share()
        .eraseToAnyPublisher()
    
    lazy var answeredInvites = NotificationCenter.default.publisher(
        for: ApplicationCallState.CallStateLocalAnswerNotification
    )
        .map { n  in n.userInfo?["callId"] as? String}
        .compactMap { $0 }
        .combineLatest(self.activeInvites)
        .flatMap { callId, invites in
            guard let invite = invites[callId] else {
                return Just(Result<VGVoiceCall,Error>.failure(NSError())).eraseToAnyPublisher()
            }
            return Future{ p in
                invite.answer { err, call in
                    (err != nil) ? p(Result.failure(err!)) : p(Result.success(call!))
                }
            }
            .map { vgcall in
                Result<VGVoiceCall,Error>.success(vgcall)
            }
            .catch { err in
                Just(Result<VGVoiceCall,Error>.failure(err))
            }
            .eraseToAnyPublisher()
        }
        .share()
    
    
    lazy var RejectedInvites = NotificationCenter.default.publisher(
        for: ApplicationCallState.CallStateLocalRejectNotification
    )
        .map { n  in n.userInfo?["callId"] as? String}
        .compactMap { $0 }
        .combineLatest(self.activeInvites)
        .flatMap { callId, invites in
            guard let invite = invites[callId] else {
                return Just(Result<Void,Error>.failure(NSError())).eraseToAnyPublisher()
            }
            return Future{ p in
                invite.reject { err in
                    (err != nil) ? p(Result.failure(err!)) : p(Result.success(()))
                }
            }
            .map { _ in
                Result<Void,Error>.success(())
            }
            .catch { err in
                Just(Result<Void,Error>.failure(err))
            }
            .eraseToAnyPublisher()
        }
        .share()
    
    lazy var activeInvites = self.vonageInvites
        .map { ($0.call, invite:$0.invite as VGVoiceInvite?)}
        .merge(with:
                self.vonageCallHangup.map { ($0.call, invite:nil)}
        )
        .merge(with:
            self.vonageLegStatus
            .filter { $0.status == VonageLegStatusAnswered }
            .map { ($0.call, invite:nil) }
        )
        .scan(Dictionary<String,VGVoiceInvite>()){ all, update in
            var new = all
            if (update.invite == nil ) { new.removeValue(forKey: update.0)  }
            else { new[update.0] = update.invite }
            return new
        }
    
    /// We reduce our outbound calls and answered inbound calls into a map
    /// representing our active call objects
    lazy var activeVGCalls = self.answeredInvites
        .compactMap { try? $0.get() }
        .merge(with:
                outboundVGCalls.compactMap { try? $0.get() }
        )
        .map { (callId:$0.callId, $0 as VGVoiceCall?)}
        .merge(with: self.vonageCallHangup.map {($0.call, nil)} )
        .scan(Dictionary<CallId,VGVoiceCall>()) { all, update  in
            var new = all
            if (update.1 == nil ) { new.removeValue(forKey: update.callId)  }
            else { new[update.callId] = update.1 }
            return new
        }
        .multicast(subject: CurrentValueSubject([:]))
        .autoconnect()
        
    
    lazy var localHangups = NotificationCenter.default.publisher(for: ApplicationCallState.CallStateLocalHangupNotification)
        .compactMap { n  in n.userInfo!["callId"] as? String}
        .combineLatest(self.activeVGCalls)
        .flatMap { (callId:String, calls:[String:VGVoiceCall]) in
            guard let call = calls[callId] else {
                return Just((call:callId,err:NSError() as Error?)).eraseToAnyPublisher()
            }
            return Future<CallActionResult,Error>{ p in
                call.hangup { err in
                    print("foo3", err)
                    p(Result.success((call:callId, err:nil)))
                }
            }
            .catch { err in
                Just((call:callId,err:err))
            }
            .eraseToAnyPublisher()
        }
        .share()
    
    
}
