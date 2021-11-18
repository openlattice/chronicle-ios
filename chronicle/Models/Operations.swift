//
//  Operations.swift
//  Operations
//
//  Created by Alfonce Nzioka on 11/16/21.
//

/*
 classes and functions for fetching and adding sensor data entries to database
 */
import Foundation
import CoreData
import OSLog

class MockSensorDataOperation: Operation {
    private let logger = Logger(subsystem: "com.openlattice.chronicle", category: "MockSensorDataOperation")

    private let context: NSManagedObjectContext
    
    private var timezone: String {
        TimeZone.current.identifier
    }

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    override func main() {

        let numEntries = Int.random(in: 50...100)
        context.performAndWait {
            do {
                for _ in 0..<numEntries {
                    let now = Date()
                    let start = now - (60 * 60) // 1hr before
                    let end = now + (60 * 60) // 1hr after
                    let sensorType = SensorType.allCases.randomElement()!

                    let object = SensorData(context: context)
                    object.id = UUID.init().uuidString
                    object.sensorType = sensorType.rawValue
                    object.startTimestamp = start.toISOFormat()
                    object.endTimestamp = end.toISOFormat()
                    object.writeTimestamp = now.toISOFormat()
                    object.timezone = timezone
                    object.data = SensorDataMock.createMockData(sensorType: sensorType)

                    try context.save()
                }
                logger.info("saved \(numEntries) SensorData objects to database")

            } catch {
                logger.error("error saving mock data to database: \(error.localizedDescription)")
            }
        }
    }
}

class UploadDataOperation: Operation {
    private let logger = Logger(subsystem: "com.openlattice.chronicle", category: "UploadDataOperation")

    private let context: NSManagedObjectContext
    private var propertyTypeIds: [FullQualifiedName: String] = [:]

    private let fetchLimit = 200

    private var uploading = false
    private var hasMoreData = false

    private var timezone: String {
        TimeZone.current.identifier
    }

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    override func start() {
        willChangeValue(forKey: #keyPath(isExecuting))
        self.hasMoreData = true
        didChangeValue(forKey: #keyPath(isExecuting))
        // get property type ids
        Task.init {
            self.propertyTypeIds = await (ApiClient.getPropertyTypeIds() ?? [:])
            main()
        }
    }


    override func main() {
        let deviceId = UserDefaults.standard.object(forKey: UserSettingsKeys.deviceId) as? String ?? ""
        guard !deviceId.isEmpty else {
            logger.error("invalid deviceId")
            return
        }

        let enrollment = Enrollment.getCurrentEnrollment()
        guard enrollment.isValid else {
            logger.error("unable to retrieve enrollment details")
            return
        }

        // try fetching
        context.performAndWait {
            do {
                while hasMoreData {
                    let fetchRequest: NSFetchRequest<SensorData>
                    fetchRequest = SensorData.fetchRequest()
                    fetchRequest.fetchLimit = fetchLimit

                    let objects = try context.fetch(fetchRequest)

                    // no data available. signal operation to terminate
                    if objects.isEmpty {
                        willChangeValue(forKey: #keyPath(isExecuting))
                        willChangeValue(forKey: #keyPath(isFinished))
                        self.hasMoreData = false
                        self.uploading = false
                        didChangeValue(forKey: #keyPath(isExecuting))
                        didChangeValue(forKey: #keyPath(isFinished))
                        break
                    }

                    if isCancelled {
                        break
                    }

                    // transform to Data
                    let data = try transformSensorDataForUpload(objects)

                    self.logger.info("attempting to upload \(objects.count) objects to server")
                    self.uploading = true

                    ApiClient.uploadData(sensorData: data, enrollment: enrollment, deviceId: deviceId) {
                        self.logger.info("successfully uploaded \(objects.count) to server")
                        objects.forEach (self.context.delete) // delete uploaded data from local db
                        try? self.context.save()
//                        PersistenceController.shared.lastUploaded = Date()
                        // record last successful upload
                        UserDefaults.standard.set(Date().toISOFormat(), forKey: UserSettingsKeys.lastUploadDate)
                        self.uploading = false
                    } onError: { error in
                        self.logger.error("error uploading to server: \(error)")

                        // signal operation to terminate
                        self.willChangeValue(forKey: #keyPath(isExecuting))
                        self.willChangeValue(forKey: #keyPath(isFinished))
                        self.uploading = false
                        self.hasMoreData = false
                        self.didChangeValue(forKey: #keyPath(isExecuting))
                        self.didChangeValue(forKey: #keyPath(isFinished))
                    }

                    // wait until the current upload attempt complete, and try again if there is more data
                    while self.uploading {
                        Thread.sleep(forTimeInterval: 5)
                    }
                }

            } catch {
                logger.error("error uploading data to server: \(error.localizedDescription)")
                uploading = false
            }
        }
    }

    override var isExecuting: Bool {
        return hasMoreData
    }

    override var isAsynchronous: Bool {
        return true
    }

    override var isFinished: Bool {
        return !hasMoreData
    }

    private func transformSensorDataForUpload(_ data: [SensorData]) throws -> Data {

        guard let namePTID = self.propertyTypeIds[FullQualifiedName.nameFqn],
              let dateLoggedPTID = self.propertyTypeIds[FullQualifiedName.dateLoggedFqn],
              let startDateTimePTID = self.propertyTypeIds[FullQualifiedName.dateTimeStartFqn],
              let endDateTimePTID = self.propertyTypeIds[FullQualifiedName.dateTimeEndFqn],
              let idPTID = self.propertyTypeIds[FullQualifiedName.idFqn],
              let timezonePTID = self.propertyTypeIds[FullQualifiedName.timezoneFqn],
              let valuesPTID = self.propertyTypeIds[FullQualifiedName.idFqn] else {
                  throw("error getting propertyTypeIds")
              }

        let transformed: [[String: Any]] = try data.map {
            var result: [String: Any] = [:]

            if let dateRecorded = $0.writeTimestamp,
               let startDate = $0.startTimestamp,
               let endDate = $0.endTimestamp,
               let sensor = $0.sensorType,
               let id = $0.id,
               let data = $0.data {

                let toJSon = try JSONSerialization.jsonObject(with: data, options: [])

                result[namePTID] = sensor
                result[dateLoggedPTID] = dateRecorded
                result[startDateTimePTID] = startDate
                result[endDateTimePTID] = endDate
                result[idPTID] = id
                result[valuesPTID] = toJSon
                result[timezonePTID] = timezone
            }
            return result
        }

        return try JSONSerialization.data(withJSONObject: transformed, options: [])
    }

}

extension Date {

    // return random date between two dates
    static func randomBetween(start: Date, end: Date) -> Date {
        var date1 = start
        var date2 = end
        if date2 < date1 {
            swap(&date1, &date2)
        }

        let span = TimeInterval.random(in: date1.timeIntervalSinceNow...date2.timeIntervalSinceNow)
        return Date(timeIntervalSinceNow: span)
    }

    func toISOFormat() -> String {
        return ISO8601DateFormatter.init().string(from: self)
    }
}
