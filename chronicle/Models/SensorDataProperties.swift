//
//  SensorDataProperties.swift
//  chronicle
//
//  Created by Alfonce Nzioka on 1/28/22.
//  Copyright © 2022 OpenLattice, Inc. All rights reserved.
//

import Foundation
import SensorKit

// A struct encapsulating the properties of a SensorData
struct SensorDataProperties {
    let sensor: Sensor
    var duration: Double? = nil // duration that the sample spans
    let writeTimestamp: Date? // when sensor sample was recorded
    let timezone: String = TimeZone.current.identifier
    let data: Data?
    
    var isValidSample: Bool {
        return data != nil
    }
    
    init(sensor: Sensor, duration: TimeInterval?, writeTimeStamp: SRAbsoluteTime, data: Data?) {
        
        self.sensor = sensor
        self.duration = duration
        self.data = data
        
        // specific point in time relative to the absolute reference date of 1 Jan 2001 00:00:00 GMT.
        let abs = writeTimeStamp.toCFAbsoluteTime()
        
        // Date relative to 00:00:00 UTC on 1 January 2001 by a given number of seconds.
        self.writeTimestamp = Date(timeIntervalSinceReferenceDate: abs)
        
    }
}


