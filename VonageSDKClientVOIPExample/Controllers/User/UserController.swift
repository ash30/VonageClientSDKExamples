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
        let token = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJhcHBsaWNhdGlvbl9pZCI6Ijg2ZmFiM2JjLWY4ODQtNDhkNS05MTRhLTZhYTViMDc5ZGI3NiIsImFjbCI6eyJwYXRocyI6eyIvKi91c2Vycy8qKiI6e30sIi8qL2NvbnZlcnNhdGlvbnMvKioiOnt9LCIvKi9zZXNzaW9ucy8qKiI6e30sIi8qL2RldmljZXMvKioiOnt9LCIvKi9pbWFnZS8qKiI6e30sIi8qL21lZGlhLyoqIjp7fSwiLyovYXBwbGljYXRpb25zLyoqIjp7fSwiLyovcHVzaC8qKiI6e30sIi8qL2tub2NraW5nLyoqIjp7fSwiLyovY2FsbHMvKioiOnt9LCIvKi9sZWdzLyoqIjp7fX19LCJleHAiOjE2NzY1NjIyMDgsImp0aSI6IjM5YjI0YmM2LTI0MmYtNDI4Ni04NmRjLTJkNGQ0Y2QwODQ1NiIsInN1YiI6ImFzaCIsImlhdCI6MTY3NjM4OTQwOH0.sXYxPolnfiFls6lPW1T__jhPx-sI8idT2jVzicxaB3c9UkA0txEY5n_o-f_6n3qWljU-I3yE2THg6fbVfS31fxng_4H0rsPMnkUZJWVKr5ssRqz7VD7S3WHNJzAGMeBvqBQ_23STTSplMec9GohUUV9Hy1M0fEcZkWEZyBTqHF1CImUwK_T1JmfiE93BbaTKe9_DZ_3CiJwdUiUAPPU8FGais4cyaLSxB0OlYorYWE1azB_ILEUqA_Yh3iwIw4JORLaDtzsE_ToCxVzKR3mrCquarO5nxKkxPga8KSfMXLiqgbWOV3T0QX_yWeqePGgTJh6mn_72aoPUFV5eD-pAow"
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
