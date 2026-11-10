import Foundation
import FITSwiftSDK

/// Deterministic synthetic FIT files use the exact decoder and storage path as user imports.
public enum DemoFIT {
    public static func make(variant: Int = 0, multisport: Bool = false, omitSensors: Bool = false) throws -> Data {
        let encoder = Encoder()
        let start = DateTime(timestamp: 1_162_551_600 + UInt32(variant) * 86_400)
        let file = FileIdMesg()
        try file.setType(.activity)
        try file.setManufacturer(Manufacturer.development)
        try file.setProduct(1)
        try file.setSerialNumber(UInt32(variant + 1))
        try file.setTimeCreated(start)
        encoder.write(mesg: file)
        let count = multisport ? 2 : 1
        for sessionIndex in 0..<count {
            let sessionStart = DateTime(timestamp: start.timestamp + UInt32(sessionIndex * 1_800))
            let end = DateTime(timestamp: sessionStart.timestamp + 1_800)
            let startEvent = EventMesg()
            try startEvent.setTimestamp(sessionStart)
            try startEvent.setEvent(.timer)
            try startEvent.setEventType(.start)
            encoder.write(mesg: startEvent)
            let speed = sessionIndex == 1 ? 3.0 : 7.0 + Double(variant) * 0.5
            // At a session boundary only the new session owns that timestamp.
            let final = sessionIndex == count - 1 ? 360 : 359
            for i in 0...final {
                let record = RecordMesg()
                let elapsed = Double(i * 5)
                try record.setTimestamp(DateTime(timestamp: sessionStart.timestamp + UInt32(i * 5)))
                try record.setDistance(elapsed * speed)
                try record.setSpeed(speed + sin(elapsed / 90) * 0.8)
                try record.setAltitude(100 + 25 * sin(elapsed / 240))
                if !omitSensors {
                    try record.setHeartRate(UInt8(135 + Int(15 * sin(elapsed / 130)) + variant * 3))
                    try record.setPower(UInt16(190 + Int(50 * sin(elapsed / 65)) + variant * 12))
                    try record.setCadence(UInt8(80 + Int(7 * sin(elapsed / 80))))
                }
                encoder.write(mesg: record)
            }
            let stop = EventMesg()
            try stop.setTimestamp(end)
            try stop.setEvent(.timer)
            try stop.setEventType(.stopAll)
            encoder.write(mesg: stop)
            let lap = LapMesg()
            try lap.setMessageIndex(UInt16(sessionIndex))
            try lap.setTimestamp(end)
            try lap.setStartTime(sessionStart)
            try lap.setTotalElapsedTime(1_800)
            try lap.setTotalTimerTime(1_800)
            try lap.setTotalDistance(1_800 * speed)
            encoder.write(mesg: lap)
            let session = SessionMesg()
            try session.setMessageIndex(UInt16(sessionIndex))
            try session.setTimestamp(end)
            try session.setStartTime(sessionStart)
            try session.setSport(sessionIndex == 1 ? .running : .cycling)
            try session.setSubSport(.generic)
            try session.setTotalElapsedTime(1_800)
            try session.setTotalTimerTime(1_800)
            try session.setTotalDistance(1_800 * speed)
            try session.setFirstLapIndex(UInt16(sessionIndex))
            try session.setNumLaps(1)
            if !omitSensors {
                try session.setAvgHeartRate(UInt8(135 + variant * 3))
                try session.setAvgPower(UInt16(190 + variant * 12))
            }
            encoder.write(mesg: session)
        }
        let activity = ActivityMesg()
        try activity.setTimestamp(DateTime(timestamp: start.timestamp + UInt32(1_800 * count)))
        try activity.setTotalTimerTime(Double(1_800 * count))
        try activity.setNumSessions(UInt16(count))
        encoder.write(mesg: activity)
        return encoder.close()
    }
}
