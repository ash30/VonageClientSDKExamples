//
//  Call.swift
//  VonageSDKClientVOIPExample
//
//  Created by Ashley Arthur on 12/02/2023.
//

import Foundation

/// The Vonage Client offers the flexibility and freedom for customers to define their own CallModel
/// to suit their use case. In this sample application we will define a traditional PSTN one to one call model.
///
enum CallStatus {
    case ringing
    case answered
    case rejected
    case canceled
    case completed(remote:Bool)
    case unknown
}

extension CallStatus: Equatable {}

struct CallError: Error {
    let id:UUID?
    let err:Error
    
    init(id:UUID?, err:Error?){
        self.id = id
        self.err = err ?? ApplicationErrors.unknown
    }
}

typealias Call = OneToOneCall

enum OneToOneCall {
    case inbound(id:UUID, from:String, status:CallStatus)
    case outbound(id:UUID, to:String, status:CallStatus)
    
    init(call:Self, status: CallStatus){
        switch (call){
        case .inbound(let id, let from, _):
            self = .inbound(id:id, from: from, status:status )
        case .outbound(let id, let to, _):
            self = .outbound(id: id, to: to, status: status)
        }
    }
    var status: CallStatus {
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
    func nextState(input:CallUpdate) -> CallStatus {
        switch(self){
        case .inbound:
            return nextStateInbound(input:input)
        case .outbound:
            return nextStateOutbound(input:input)
        }
    }
    
    private func nextStateOutbound(input:CallUpdate) -> CallStatus {
        switch (self.status) {
        case .ringing where (input.call != input.leg && input.status == VonageLegStatusAnswered):
            return .answered
        case .ringing where input.status == VonageLegStatusCompleted:
            return .rejected
        /// We introduce a specific local status so we can differentiate local cancel from remote reject
        case .ringing where input.status == LocalComplete:
            return .canceled
        case .answered where input.status == LocalComplete:
            return .completed(remote: false)
        case .answered where input.status == VonageLegStatusCompleted:
            return .completed(remote: true)
        default:
            return self.status
        }
    }
    
    private func nextStateInbound(input:CallUpdate) -> CallStatus  {
        switch (self.status) {
        case .ringing where input.call == input.leg && input.status == VonageLegStatusAnswered:
            return .answered
        case .ringing where input.status == VonageLegStatusCompleted:
            return .canceled
        case .ringing where input.status == LocalComplete:
            return .rejected
        case .answered where input.status == LocalComplete:
            return .completed(remote: false)
        case .answered where input.status == VonageLegStatusCompleted:
            return .completed(remote: true)
        default:
            return self.status
        }
    }
}
