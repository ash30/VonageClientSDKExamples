//
//  helper.swift
//  VonageSDKClientVOIPExample
//
//  Created by Ashley Arthur on 02/02/2023.
//

import Foundation

enum Either<L,R> {
    case left(value:L)
    case right(value:R)
}

extension Either {
  public var leftValue: L? {
    switch self {
    case .left(let leftValue): return leftValue
    case .right: return nil
    }
  }

  public var rightValue: R? {
    switch self {
    case .right(let rightValue): return rightValue
    case .left: return nil
    }
  }
}
