//
//  ServiceType.swift
//  stcp-app
//
//  Created by Nuno Rios on 14/06/2026.
//

import Foundation

nonisolated public enum ServiceType: Int, Codable {
    private static let weekdayServiceId = "DIAS UTEIS"
    private static let saturdayServiceId = "SÁBADOS"
    private static let sundayServiceId = "DOMINGOS|FERIADOS"
    
    case weekday = 0
    case saturday = -1
    case sundayOrFeriado = 1
    
    public var serviceId: String {
        switch self {
        case .weekday:
            return Self.weekdayServiceId
        case .saturday:
            return Self.saturdayServiceId
        case .sundayOrFeriado:
            return Self.sundayServiceId
        }
    }
    
    public static func defaultServiceType(for date: Date = Date()) -> ServiceType {
        let weekday = DateUtil.portoCalendar.component(.weekday, from: date)
        switch weekday {
        case 1:
            return .sundayOrFeriado
        case 7:
            return .saturday
        default:
            return .weekday
        }
    }
}
