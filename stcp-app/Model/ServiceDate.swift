//
//  ServiceDate.swift
//  stcp-app
//
//  Created by Nuno Rios on 16/09/2026.
//

import SwiftData

@Model
public final class ServiceDate {
    
    // yyyymmdd
    @Attribute(.unique)
    public private(set) var date: Int
    
    public private(set) var serviceType: ServiceType
    
    public init(date: Int, serviceType: ServiceType) {
        self.date = date
        self.serviceType = serviceType
    }
}
