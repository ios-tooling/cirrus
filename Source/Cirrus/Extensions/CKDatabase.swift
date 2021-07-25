//
//  CKDatabase.swift
//  Cirrus
//
//  Created by Ben Gottlieb on 7/17/21.
//

import Suite
import CloudKit

public extension CKDatabase {
	func records(ofType type: CKRecord.RecordType, matching predicate: NSPredicate = NSPredicate(value: true), sortedBy: [NSSortDescriptor] = [], in zoneID: CKRecordZone.ID? = nil) -> AsyncRecordSequence {
		let query = CKQuery(recordType: type, predicate: predicate)
		query.sortDescriptors = sortedBy
		
		
		let seq = AsyncRecordSequence(query: query, in: self, zoneID: zoneID)
		seq.start()
		return seq
	}

	func changes(in zoneIDs: [CKRecordZone.ID], fromBeginning: Bool = false) -> AsyncZoneChangesSequence {
		if fromBeginning {
			Cirrus.instance.localState.zoneChangeTokens = [:]
		}
		let seq = AsyncZoneChangesSequence(zoneIDs: zoneIDs, in: self)
		seq.start()

		return seq
	}
	
	func delete(recordIDs: [CKRecord.ID]?) async throws -> [CKRecord.ID] {
		guard let ids = recordIDs, ids.isNotEmpty else { return [] }
		
		let op = CKModifyRecordsOperation(recordIDsToDelete: recordIDs)
		do {
			return try await op.delete(from: self)
		} catch {
			await Cirrus.instance.handleReceivedError(error)
			throw error
		}
	}
	
	func save(records: [CKRecord]?, atomically: Bool = true, conflictResolver: ConflictResolver? = nil) async throws {
		guard let records = records, records.isNotEmpty else { return }
		let op = CKModifyRecordsOperation(recordsToSave: records)
		var resolver = conflictResolver
		if resolver == nil { resolver = await Cirrus.instance.configuration.conflictResolver }

		do {
			try await op.save(in: self)
		} catch {
			if let updatedRecords = try await resolver?.resolve(error: error, in: records, database: self) {
				try await save(records: updatedRecords, atomically: atomically, conflictResolver: conflictResolver)
			} else {
				await Cirrus.instance.handleReceivedError(error)
				throw error
			}
		}
	}
	
	func save(record: CKRecord?, conflictResolver: ConflictResolver? = nil) async throws {
		guard let record = record else { return }
		try await save(records: [record], conflictResolver: conflictResolver)
	}

	func delete(record: CKRecord?) async throws {
		guard let record = record else { return }
		let op = CKModifyRecordsOperation(recordIDsToDelete: [record.recordID])
		_ = try await op.delete(from: self)
	}
	
	func fetchRecord(withID id: CKRecord.ID) async throws -> CKRecord? {
		do {
			return try await record(for: id)
		} catch let error as CKError {
			switch error.code {
			case .unknownItem:
				return nil
				
			default:
				await Cirrus.instance.handleReceivedError(error)
				throw error
			}
		}
	}
	
	func setupSubscriptions(_ subs: [Cirrus.SubscriptionInfo]) async {
		let ids = subs.map { $0.id(in: self.databaseScope) }
		let op = CKFetchSubscriptionsOperation(subscriptionIDs: ids)
		
		do {
			let existing = try await op.fetchAll(in: self)
			let newSubs = subs.filter { existing[$0.id(in: databaseScope)] == nil }.map { $0.subscription(in: databaseScope) }
			
			let modifyOp = CKModifySubscriptionsOperation(subscriptionsToSave: newSubs, subscriptionIDsToDelete: nil)
			try await modifyOp.save(in: self)
		} catch {
			logg(error: error, "Failed to fetch/setup subscriptions")
			await Cirrus.instance.handleReceivedError(error)
		}
		
	}
	
}

extension CKDatabase {
	public func deleteAll(from recordTypes: [CKRecord.RecordType], in zone: CKRecordZone? = nil) async throws {
		var ids: [CKRecord.ID] = []
		
		for recordType in recordTypes {
			let seq = AsyncRecordSequence(recordType: recordType, desiredKeys: [], in: self, zoneID: zone?.zoneID)
			
			seq.start()
			for try await record in seq {
				ids.append(record.recordID)
			}
		}
		
		let chunkSize = 30
		let idChunks = ids.breakIntoChunks(ofSize: chunkSize)
		
		for chunk in idChunks {
			do {
				let deleted = try await delete(recordIDs: chunk)
				if deleted.count != chunk.count {
					logg("Failed to delete some records (attempted \(chunk.count), succeeded on \(deleted.count).")
				}
			} catch {
				logg(error: error, "Error when deleting")
			}
		}
		
		print("Done")
	}
}


extension CKDatabase.Scope: Codable {
	var database: CKDatabase {
		switch self {
		case .private: return Cirrus.instance.container.privateCloudDatabase
		case .public: return Cirrus.instance.container.publicCloudDatabase
		case .shared: return Cirrus.instance.container.sharedCloudDatabase
		default: return Cirrus.instance.container.privateCloudDatabase
		}
	}
	static var allScopes: [CKDatabase.Scope] {
		[.private, .public, .shared]
	}
	
	var name: String {
		switch self {
		case .private: return "private"
		case .public: return "public"
		case .shared: return "shared"
		default: return "\(rawValue)"
		}
	}
}
