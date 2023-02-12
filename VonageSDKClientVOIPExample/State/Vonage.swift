//
//  Vonage.swift
//  VonageSDKClientVOIPExample
//
//  Created by Ashley Arthur on 05/02/2023.
//

import Foundation
import VonageClientSDKVoice
import Combine
import UIKit
import CallKit


/// # Vonage Client Publisher Adaption
/// For the sake of our demo application, we are going to convert the delegate interface of the client sdk into a series of combine publishers.
/// The sdk is flexible enough to accomodate any programming style but we choose observables/publishers today
/// for their declarative nature and strong code locality.
///
///

class VonageClientState: NSObject, VGVoiceClientDelegate {
    
    let client: VGVoiceClient
    private let appState: ApplicationState

    private var cancellables = Set<AnyCancellable>()
    
    init(vonageClient:VGVoiceClient, applicationState:ApplicationState){
        self.client = vonageClient
        self.appState = applicationState
        super.init()
        vonageClient.delegate = self
        
        bind(application: applicationState)
        
        // Refactor please
        self.activeInvites.sink(receiveValue: {_ in}).store(in: &cancellables)
        self.activeVGCalls.sink(receiveValue: {_ in}).store(in: &cancellables)
        self.answeredInvites.sink(receiveValue: {_ in}).store(in: &cancellables)
        self.RejectedInvites.sink(receiveValue: {_ in}).store(in: &cancellables)
    }
    
    /// ## Basic Publishers
    /// Here we pipe the delegate methods into subjects so we can compose within our publishers
    /// This part is mostly boiler plate adapter stuff

    // MARK: VGVoiceClientDelegate Sessions
    
    /// The session is an object representing the connection with the vonage backend.
    /// We translate the session callbacks into a unified observable to represent a generalised concept of connection.
    ///
    let vonageWillReconnect = PassthroughSubject<Void, Never>()
    func clientWillReconnect(_ client: VGBaseClient) {
        vonageWillReconnect.send(())
    }
    
    let vonagedidReconnect = PassthroughSubject<Void, Never>()
    func clientDidReconnect(_ client: VGBaseClient) {
        vonagedidReconnect.send(())
    }
    
    let vonageSessionError = PassthroughSubject<VGSessionErrorReason, Never>()
    func client(_ client: VGBaseClient, didReceiveSessionErrorWith reason: VGSessionErrorReason) {
        vonageSessionError.send(reason)
    }
    
    // MARK: VGVoiceClientDelegate Invites
    
    /// For inbound calls, the sdk will receive invite object from this callback
    ///
    let vonageInvites = PassthroughSubject<(call:UUID,invite:VGVoiceInvite), Never>()
    func voiceClient(_ client: VGVoiceClient, didReceiveInviteForCall callId: String, with invite: VGVoiceInvite) {
        vonageInvites.send((call:UUID(uuidString: callId)!, invite:invite))
    }
    
    // MARK: VGVoiceClientDelegate LegStatus

    /// Leg Status update callbacks are how we understand what is happening to the individual connections
    /// within a single 'call'
    ///
    let vonageLegStatus = PassthroughSubject<(call:UUID,leg:UUID,status:String), Never>()
    func voiceClient(_ client: VGVoiceClient, didReceiveLegStatusUpdateForCall callId: String, withLegId legId: String, andStatus status: String) {
        vonageLegStatus.send((UUID(uuidString: callId)!,UUID(uuidString: legId)!,status))
    }
    
    /// RTC hangup is special form of leg status update. Normally leg updates only fire for a leg once its joined a call.
    /// But for some cases in the classic 1 to 1 call model ie cancel, reject - the leg doesn't ever join the call.
    /// RTC Hangup will always fire for your leg when its terminated by the backend, so we can use it as 'completed' leg status event
    ///
    let vonageCallHangup = PassthroughSubject<(call:UUID,leg:UUID,status:String), Never>()
    func voiceClient(_ client: VGVoiceClient, didReceiveHangupForCall callId: String, withLegId legId: String, andQuality callQuality: VGRTCQuality) {
        vonageCallHangup.send((call:UUID(uuidString: callId)!,leg:UUID(uuidString: legId)!, VonageLegStatusCompleted))
    }
    
    /// ## Higher level Publishers
    /// Now that we have the delegate methods as publishers - we can create higher level, more convenient publishers
    /// for integration with the rest of the app.
    
    // MARK: Session
    
    /// We transfrom the logged in user into a corresponding vonage session and publish for other subscribers
    lazy var session = NotificationCenter.default.publisher(
        for: ApplicationCallState.CallStateConnectionStart
    )
        .combineLatest(self.appState.user)
        .compactMap { _, user in user }
        .map {
            self.appState.vonageServiceToken.flatMap { token in
                Future<String?,Error> { p in
                    self.client.createSession(token) { err, session in
                        p(err != nil ? Result.failure(err!) : Result.success(session!))
                    }
                }
                .eraseToAnyPublisher()
            }
            .catch { _ in Just(nil) }
            .merge(with: self.vonageSessionError.map { _ in nil }.first())
        }
        .switchToLatest()
        .multicast(subject: CurrentValueSubject<String?,Never>(nil))
        .autoconnect()
        .eraseToAnyPublisher()
        
    
    lazy var pushRegistration = self.session.compactMap { $0 }
        .combineLatest(self.appState.deviceToken, self.appState.voipToken)
        .flatMap { values in
            Future { p in
                self.client.registerDevicePushToken(values.2, userNotificationToken: values.1, isSandbox:true) {
                    err, device in
                    err != nil ? p(Result.failure(ApplicationErrors.PushNotRegistered)) : p (Result.success(true))
                }
            }
            .catch { _ in Just(false) }
        }
        .first(where: {$0 == true})
        .multicast(subject: CurrentValueSubject<Bool,Never>(false))
        .autoconnect()
        .eraseToAnyPublisher()

    
    // MARK: Calls
    
    func bind(application:ApplicationState) {
    }

    /// When the UI layer notifies us of the intention to create an outbound call, we can transform those signals into
    /// actual VGCall Objects.
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
    
    /// Similar to outbound calls, we can transform inbound invitations from the sdk in to Calls
    /// if we combine them with notifications from the UI layer
    lazy var answeredInvites = NotificationCenter.default.publisher(
        for: ApplicationCallState.CallStateLocalAnswerNotification
    )
        .map { n  in n.userInfo?["callId"] as? UUID}
        .compactMap { $0 }
        .flatMap { callId in
            self.activeInvites.first()
                .flatMap { invites in
                    invites[callId].map { invite in
                        Future{ p in
                            invite.answer { err, call in
                                (err != nil) ? p(Result.failure(err!)) : p(Result.success(call!))
                            }
                        }
                        .asResult()
                    } ?? Just(Result<VGVoiceCall,Error>.failure(ApplicationErrors.unknown)).eraseToAnyPublisher()
                }
                .eraseToAnyPublisher()
        }
        .share()
    
    
    lazy var RejectedInvites = NotificationCenter.default.publisher(
        for: ApplicationCallState.CallStateLocalRejectNotification
    )
        .map { n  in n.userInfo?["callId"] as? UUID}
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
    
    /// For both invites and calls, we need to keep reference to the objects the SDK hands to us
    /// The following the two observables reduce over the previously defined streams of invites/calls
    /// to return a single Dictionary holding reference.
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
        .scan(Dictionary<UUID,VGVoiceInvite>()){ all, update in
            var new = all
            if (update.invite == nil ) { new.removeValue(forKey: update.0)  }
            else { new[update.0] = update.invite }
            return new
        }
        .multicast(subject: CurrentValueSubject([:]))
        .autoconnect()
    
    lazy var activeVGCalls = self.answeredInvites
        .compactMap { try? $0.get() }
        .merge(with:
                outboundVGCalls.compactMap { try? $0.get() }
        )
        .map { (callId:UUID(uuidString: $0.callId)!, $0 as VGVoiceCall?)}
        .merge(with: self.vonageCallHangup.map {($0.call, nil)} )
        .scan(Dictionary<UUID,VGVoiceCall>()) { all, update  in
            var new = all
            if (update.1 == nil ) { new.removeValue(forKey: update.callId)  }
            else { new[update.callId] = update.1 }
            return new
        }
        .multicast(subject: CurrentValueSubject([:]))
        .autoconnect()
}


// MOVE

extension Publisher {
    
    func asResult() -> AnyPublisher<Result<Output, Failure>, Never> {
        self.map(Result.success)
            .catch { error in
                Just(.failure(error))
            }
            .eraseToAnyPublisher()
    }
    
    func retryWithBackoff(n:Int=1,delay:Int=10) -> AnyPublisher<Output,Failure> {
        let atttempts = Swift.max(1, n)
        Array(0...atttempts).publisher
            .delay(for: .seconds(3*(atttempts-1)), scheduler: RunLoop.main, options: .none)
            .flatMap {
                self.replaceError(with: nil)
            }
            
        
    }
    
    
    func repeating<T>(attempts:Int, callback:@escaping (Output, Int)-> AnyPublisher<T,Failure>) -> AnyPublisher<T, Failure> {
        
        self.flatMap { input in
            Array(0...attempts).publisher
                .map { (n:Int) -> AnyPublisher<T,Failure> in
                    callback(input,n)
                }
                .flatMap(maxPublishers: Subscribers.Demand.max(1), { $0 })
                .eraseToAnyPublisher()
        }
        .eraseToAnyPublisher()
    }
    
    public func asResult2<T>(callback:@escaping (Output, @escaping Future<T,Error>.Promise) -> Void) -> AnyPublisher<Result<T, Error>, Failure> {
        
        self.flatMap { arg in
            Future { p in
                callback(arg,p)
            }
            .asResult()
        }
        .eraseToAnyPublisher()
    }
    
}


