//
//  AppActions.swift
//  VonageSDKClientVOIPExample
//
//  Created by Ashley Arthur on 13/02/2023.
//

import Foundation
import Combine
import UIKit
import CallKit

enum ApplicationAction {
    case initialisePush
    case cpaasConnect
    case userAuth(uname:String,pword:String)
    case newOutboundCall(context:[String:Any])
    case answerInboundCall(id:UUID, cxAction:CXAnswerCallAction?)
    case rejectInboundCall(id:UUID)
    case hangupCall(id:UUID, cxAction:CXEndCallAction?)
}

struct AppActionTransaction {
    let action: ApplicationAction
    let tid: UUID
    let callid: UUID?
}
struct AppActionResult<T> {
    let tid:UUID
    let callid: UUID?
    let result: Result<T,Error>
    
    func asAnyResult() -> AppActionResult<Any> {
        return AppActionResult<Any>(tid: self.tid, callid: self.callid, result: self.result.map {$0 as Any})
    }
}
typealias AnyAppActionResult = AppActionResult<Any>


extension ApplicationAction {
    
    fileprivate static let ApplicationActionNotification = NSNotification.Name("ApplicationActionNotification")
    
    static let publisher: AnyPublisher<AppActionTransaction,Never> = {
        return NotificationCenter.default
            .publisher(for: ApplicationAction.ApplicationActionNotification)
            .compactMap { n  in n.userInfo!["transaction"] as? AppActionTransaction}
            .eraseToAnyPublisher()
    }()
    
    static func post(_ action:ApplicationAction) {
        post(action, tid: UUID())
    }
    
    static func post(_ action:ApplicationAction, tid:UUID) {
        var callId:UUID? = nil
        switch (action){
        case let .answerInboundCall(id,_): callId = id
        case let .rejectInboundCall(id): callId = id
        case let .hangupCall(id,_): callId = id
        default: callId = nil
        }
        
        NotificationCenter.default.post(name: ApplicationAction.ApplicationActionNotification, object:nil, userInfo: ["action": action, "transaction": AppActionTransaction(action: action, tid: tid, callid: callId)])
    }
    
}
