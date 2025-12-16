//
//  Item.swift
//  aethermaze
//
//  Created by Marc L. Melcher on 12/16/25.
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
