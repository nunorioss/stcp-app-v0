//
//  TripConfig.swift
//  stcp-app
//
//  Created by Nuno Rios on 21/09/2026.
//

import SwiftData

@Model
public final class TripConfig {
    @Attribute(.unique)
    public private(set) var id: String = "main"
    
    //TODO: Better name?
    var globalTripNo: String
    
    init(globalTripNo: String) {
        self.globalTripNo = globalTripNo
    }
}
