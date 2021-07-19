//
//  Cirrus+Sync.swift
//  Cirrus+Sync
//
//  Created by Ben Gottlieb on 7/19/21.
//

import CloudKit
import CoreData

extension Cirrus {
	func syncContext(_ context: NSManagedObjectContext) async throws {
		let unsyncedObjects = context.unsyncedObjects.sorted { self.configuration.shouldEntity($0.entity, sortBefore: $1.entity) }
		
		for database in [container.privateCloudDatabase, container.publicCloudDatabase, container.sharedCloudDatabase] {
			let records = unsyncedObjects.filter { $0.database == database }.compactMap { CKRecord($0) }
			if records.isEmpty { continue }
			try await database.save(records: records)
		}
	}
}
