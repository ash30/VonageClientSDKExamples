//
//  AppState.swift
//  VonageSDKClientVOIPExample
//
//  Created by Ashley Arthur on 14/02/2023.
//

import Foundation
import Combine
import UIKit
import PushKit
import CallKit

protocol ApplicationController {
    func bindToApplicationState(_ state:ApplicationState)
}

class ApplicationState: ObservableObject {

    // User
    @Published var user:User? = nil
    @Published var vonageToken: String? = nil
    
    // Calls
    @Published var connection: Connection = .disconnected(err: nil)
    let newCalls = PassthroughSubject<CallStream,Never>()
    
    // CallKit
    let newCXActions = PassthroughSubject<CXAction,Never>()
    
    // Push
    @Published var deviceToken: Data? = nil
    @Published var voipToken: Data? = nil
    let voipPush = PassthroughSubject<PKPushPayload,Never>()
    
    // APP
    let transactions = PassthroughSubject<AnyAppActionResult,Never>()
}
 
