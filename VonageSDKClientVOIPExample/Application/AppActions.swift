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

extension ApplicationAction {
    
    fileprivate static let ApplicationActionNotification = NSNotification.Name("ApplicationActionNotification")
    
    static let publisher: AnyPublisher<ApplicationAction,Never> = {
        return NotificationCenter.default
            .publisher(for: ApplicationAction.ApplicationActionNotification)
            .compactMap { n  in n.userInfo!["action"] as? ApplicationAction}
            .eraseToAnyPublisher()
    }()
    
    static func post(_ action:ApplicationAction) {
        NotificationCenter.default.post(name: ApplicationAction.ApplicationActionNotification, object:nil, userInfo: ["action": action])
    }
    
}
