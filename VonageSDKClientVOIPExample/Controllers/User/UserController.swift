//
//  Auth.swift
//  VonageSDKClientVOIPExample
//
//  Created by Ashley Arthur on 25/01/2023.
//

import Foundation
import Combine
 
class UserController: NSObject {    
}

extension UserController {
        
    func generateVonageServiceToken(userName: String, callback:(String?)->Void) {
        let token = ""
        callback(token)
    }
}


extension UserController: ApplicationController {
    
    func bindToApplicationState(_ state: ApplicationState) {
        
        // User
        let user = ApplicationAction
            .publisher
            .compactMap { if case let .userAuth(uname,pword) = $0 { return (uname,pword) }; return nil }
            .map { User(uname: $0.0) as User? }
            .share()
        
        user
            .eraseToAnyPublisher()
            .assign(to: &state.$user)
    
        user
            .compactMap { $0 }
            .flatMap { u in
                Future<String?, Error>{ p in
                    self.generateVonageServiceToken(userName: u.uname) { token in
                        p(token != nil ? Result.success(token!) : Result.failure(ApplicationErrors.Unauthorised))
                    }
                }
                .catch { _ in Just(nil as String?) }
            }
            .assign(to: &state.$vonageToken)
    }
}
