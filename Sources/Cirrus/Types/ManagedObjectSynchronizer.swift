//
//  ManagedObjectSynchronizer.swift
//  ManagedObjectSynchronizer
//
//  Created by Ben Gottlieb on 7/18/21.
//

import Suite
import CoreData
import CloudKit

public protocol ManagedObjectSynchronizer {
	func process(downloadedChange change: CKRecordChange, from: CKDatabase) async
	func finishImporting() async
	func startSync()
	func uploadLocalChanges() async
}

public class SimpleObjectSynchronizer: ManagedObjectSynchronizer {
	let context: NSManagedObjectContext
	let connector: ReferenceConnector
	weak var syncStartTimer: Timer?
	
	public init(context: NSManagedObjectContext) {
		self.context = context
		self.connector = ReferenceConnector(context: context)
	}
	
	public func finishImporting() async {
		await context.perform {
			self.connector.connectUnresolved()
			self.context.saveContext(toDisk: true)
		}
	}
	
	public func startSync() {
		syncStartTimer?.invalidate()
		DispatchQueue.onMain(async: true) {
			self.syncStartTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { _ in
				Task() {
					await self.uploadLocalChanges()
				}
			}
		}
	}
	
	struct ModifiedRecord: CKRecordProviding {
		let record: CKRecord
		let modifiedAt: Date?
	}
	
	public func uploadLocalChanges() async {
		if Cirrus.instance.state.isOffline { return }
		let syncableEntities = Cirrus.instance.configuration.entities ?? []
		var pending: [CKDatabase.Scope: [ModifiedRecord]] = [:]
		let queuedDeletions = QueuedDeletions.instance.pending

		await context.perform {
			for entity in syncableEntities {
				let changed = self.context.changedRecords(named: entity.entityName)
				for object in changed {
					guard let record = CKRecord(object) else { continue }
					let scope = object.database.databaseScope
					if queuedDeletions.contains(recordID: record.recordID, in: scope) { continue }
					var current = pending[scope] ?? []
					current.append(ModifiedRecord(record: record, modifiedAt: object.locallyModifiedAt))
					pending[scope] = current
				}
			}
		}
		
		for scope in CKDatabase.Scope.allScopes {
			let deletions = queuedDeletions.deletions(in: scope.database)
			do {
				let deleted = try await scope.database.delete(recordIDs: deletions)
				QueuedDeletions.instance.clear(deleted: deleted.map { QueuedDeletions.Deletion(recordName: $0.recordName, scope: scope) })
			} catch {
				logg(error: error, "Failed to delete records: \(deletions)")
			}
		}
			
		for (scope, records) in pending {
			do {
				try await scope.database.save(records: records)
			} catch {
				logg(error: error, "Failed to save records: \(records)")
			}
		}
		
	}
	
	public func process(downloadedChange change: CKRecordChange, from database: CKDatabase) async {
		guard let recordType = change.recordType, let info = Cirrus.instance.configuration.entityInfo(for: recordType) else { return }
		
		let idField = Cirrus.instance.configuration.idField
		let resolver = Cirrus.instance.configuration.conflictResolver
		do {
			switch change {
			case .changed(let id, let remote):
				try await context.perform {
					if let object = info.record(with: id, in: self.context) {
						let local = CKRecord(object)
						let winner = resolver.resolve(local: local, localModifiedAt: object.locallyModifiedAt, remote: remote)
						
						switch winner {
						case .local:
							object.add(status: .hasLocalChanges)
							
						case .remote:
							try object.load(cloudKitRecord: remote, using: self.connector, from: database)
						}
						
					} else {
						let object = self.context.insertEntity(named: info.entityDescription.name!) as! SyncedManagedObject
						object.cirrus_changedKeys = []
						object.setValue(id.recordName, forKey: idField)
						try object.load(cloudKitRecord: remote, using: self.connector, from: database)
					}
				}
				
			case .deleted(let id, _):
				await context.perform {
					if let object = info.record(with: id, in: self.context) {
						self.context.delete(object)
					}
				}
				
			case .badRecord: break
			}
		} catch {
			cirrus_log("Failed to change: \(error)")
		}
	}
}


