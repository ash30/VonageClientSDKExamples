//
//  Auth.swift
//  VonageSDKClientVOIPExample
//
//  Created by Ashley Arthur on 25/01/2023.
//

/// We create a simple implementation for user session / identity
/// Its the applications responsibility to provide the Vonage Client with a valid JWT token
/// which assumedly will be tied to their existing user auth flow.
 
typealias UserCredentials = (uname:String, pword:String)

struct UserDetails: Hashable {
    let userName:String
}

protocol UserIdentityManager: AnyObject {
    var delgate: UserIdentityDelegate? { get set }
    func authenticate(_:UserCredentials, callback:(Error?)->Void)
    func getServiceToken(name: String, callback:(String)->Void)
}

protocol UserIdentityDelegate: AnyObject {
    func userAuthorised(userToken:String, userData:UserDetails)
    func userAuthRevoked()
}

//-------

// Dummy Implementation of User Auth
class DemoIdentityManager: UserIdentityManager {
    weak var delgate: UserIdentityDelegate? = nil
    
    func authenticate(_ np: UserCredentials, callback: (Error?) -> Void) {
        callback(nil)
        delgate?.userAuthorised(
            userToken: "", userData: UserDetails(userName:"ash")
        )
    }
    
    func getServiceToken(name: String, callback:(String)->Void) {
        let token = ""
        callback(token)
    }
}
