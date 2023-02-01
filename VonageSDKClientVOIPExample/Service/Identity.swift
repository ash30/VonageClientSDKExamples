//
//  Auth.swift
//  VonageSDKClientVOIPExample
//
//  Created by Ashley Arthur on 25/01/2023.
//
 
typealias UserCredentials = (uname:String, pword:String)

struct UserDetails {
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
        let token = "TODO"
        callback(token)
    }
}
