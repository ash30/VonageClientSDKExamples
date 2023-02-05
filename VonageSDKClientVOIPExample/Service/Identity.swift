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
        let token = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJhcHBsaWNhdGlvbl9pZCI6Ijg2ZmFiM2JjLWY4ODQtNDhkNS05MTRhLTZhYTViMDc5ZGI3NiIsImFjbCI6eyJwYXRocyI6eyIvKi91c2Vycy8qKiI6e30sIi8qL2NvbnZlcnNhdGlvbnMvKioiOnt9LCIvKi9zZXNzaW9ucy8qKiI6e30sIi8qL2RldmljZXMvKioiOnt9LCIvKi9pbWFnZS8qKiI6e30sIi8qL21lZGlhLyoqIjp7fSwiLyovYXBwbGljYXRpb25zLyoqIjp7fSwiLyovcHVzaC8qKiI6e30sIi8qL2tub2NraW5nLyoqIjp7fSwiLyovY2FsbHMvKioiOnt9LCIvKi9sZWdzLyoqIjp7fX19LCJleHAiOjE2NzU3MzI1NjEsImp0aSI6IjMwNDhiY2YyLTA4ZDEtNGY0Mi05OGU3LTM5YjUxNjNkMjRjYiIsInN1YiI6ImFzaCIsImlhdCI6MTY3NTU1OTc2MX0.CPwPW24vR5uSlF-82koZl8QxzhdHvX6Gi3Iwvpv-UGKWog7QHnlkiA7gc5ctKd8quH5aRxjm_jm7U_W91TRBgLvQdAjWT3FRHcP6bs27dHwosVKihGwD0fdLPpm5ed2oAX5nCquYf-CSgtnJkIi2cR003ZNKsK0QD4b7m6YQ_Iia04Md-zC55MprF546AgJKmKDjEqeKoE1AXoS3fxhzLMTqqs3klVzK5MElYKPdl0ZPqcLGISVH1PtK90DxKz3-dTBXajWDzoEyja9fS-r2mDK6qSTN4l8v4UXnZkpE3w4jnOCdMGE7chJqtcKjAefgYcazhTqxpN_C2S6qoAIq5Q"
        callback(token)
    }
}
