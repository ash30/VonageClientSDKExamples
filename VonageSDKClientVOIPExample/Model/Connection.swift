//
//  Connection.swift
//  VonageSDKClientVOIPExample
//
//  Created by Ashley Arthur on 12/02/2023.
//

import Foundation

enum Connection {
    case connected
    case error(err:ApplicationErrors?)
    case reconnecting
    case disconnected(err:Error?)
}
