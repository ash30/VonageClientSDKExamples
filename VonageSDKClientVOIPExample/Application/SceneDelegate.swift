//
//  SceneDelegate.swift
//  VonageSDKClientVOIPExample
//
//  Created by Ashley Arthur on 25/01/2023.
//

import UIKit
import Combine

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    var nav: UINavigationController!
    private var cancellables = Set<AnyCancellable>()

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // A new scene was added to the app.
        guard let scene = (scene as? UIWindowScene) else { return }

        self.window = UIWindow(windowScene: scene)
        self.window?.rootViewController = createViewController(LoginViewController.self)
        self.window?.makeKeyAndVisible()
        
        bind()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
    }
}

extension SceneDelegate {
    
    func bind() {
        let app =  UIApplication.shared.delegate as! AppDelegate
        let state = app.appState
        
        state.$user
            .receive(on: RunLoop.main)
            .sink { (user) in
                if (user == nil) {
                    let loginVC = self.createViewController(LoginViewController.self)
                    self.window?.rootViewController = loginVC
                }
                else {
                    let dialerVC = self.createViewController(DialerViewController.self)
                    self.window?.rootViewController = UINavigationController(rootViewController:dialerVC)
                }
                
            }
            .store(in: &cancellables)
        
        state.newCalls
            .receive(on: RunLoop.main)
            .sink { newcall in
                guard state.user != nil else {
                    return
                }
                
                if (type(of:self.nav.topViewController) != ActiveCallViewController.self) {
                    let vc = ActiveCallViewController()
                    self.nav.pushViewController(vc, animated: true)
                    newcall.first().sink { call in
                        vc.viewModel = ActiveCallViewModel(for: Just(call).merge(with: newcall))
                    }.store(in: &self.cancellables)
                }
            }
            .store(in: &cancellables)
    }
}

// MARK: Factory

extension SceneDelegate {
    
    func createViewController(_ vc:UIViewController.Type) -> UIViewController {
        let app = UIApplication.shared.delegate as! AppDelegate
        let state = app.appState
        
        switch(vc){
        case is LoginViewController.Type:
            let login = LoginViewController()
            let loginData = LoginViewModel()
            login.viewModel = loginData
            return login
        case is DialerViewController.Type:
            let dialer = DialerViewController()
            let dialerData = DialerViewModel()
            dialerData.bind(to: state)
            dialer.viewModel = dialerData
            return dialer
        case is ActiveCallViewController.Type:
            let activeCall = ActiveCallViewController()
            return activeCall
        default:
            fatalError()
        }
        
    }
    
}

