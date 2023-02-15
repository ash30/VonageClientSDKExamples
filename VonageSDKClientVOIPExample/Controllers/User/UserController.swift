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
        let token = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJhcHBsaWNhdGlvbl9pZCI6Ijg2ZmFiM2JjLWY4ODQtNDhkNS05MTRhLTZhYTViMDc5ZGI3NiIsImFjbCI6eyJwYXRocyI6eyIvKi91c2Vycy8qKiI6e30sIi8qL2NvbnZlcnNhdGlvbnMvKioiOnt9LCIvKi9zZXNzaW9ucy8qKiI6e30sIi8qL2RldmljZXMvKioiOnt9LCIvKi9pbWFnZS8qKiI6e30sIi8qL21lZGlhLyoqIjp7fSwiLyovYXBwbGljYXRpb25zLyoqIjp7fSwiLyovcHVzaC8qKiI6e30sIi8qL2tub2NraW5nLyoqIjp7fSwiLyovY2FsbHMvKioiOnt9LCIvKi9sZWdzLyoqIjp7fX19LCJleHAiOjE2NzY2NTU2NDQsImp0aSI6ImZlMDRjZWU4LTUyY2ItNDAyNy05MDNlLWU5Mzk4MDEyZWJkMyIsInN1YiI6ImFzaCIsImlhdCI6MTY3NjQ4Mjg0NH0.Be5ssW9P0oKIa__9uQVmcMjksRUzMg00mXxYup4dm4JUvvDGaPvjGa0whl_Ec1OXIl_lGbmepRwNyuk1uz5zPr3wSKysp0n4HdsYErVruI0l0imLIOze8n-7AH693nv7yPL4-GjbEdZwjuVJIOUsbJXVji63nNJvUh3f6Zwf0HF5WtKx2efCZDFjFFCK6RtXFmaX33dKNXhxrMJa9Oi7NwjbkjruyLanv7jnPf9uO0A3zSjcI314CJiTMhmqmHRO2QrEWbip2_HOXnB1MlPq43nxUW8sarNb0xaxpGlR8ij_qL6f5M31C5GVAlM9LGozdmOA417P1H7Rb4wlE3vYPw"
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
