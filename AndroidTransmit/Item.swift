//
//  Item.swift
//  AndroidTransmit
//
//  Created by cxc on 2026/9/18.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
