//
//  Item.swift
//  Project FOMO - Social Media
//
//  Created by Mustafa on 11/9/2026.
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
