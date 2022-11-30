//
//  AsyncZoneChangesSequence.swift
//  AsyncZoneChangesSequence
//
//  Created by Ben Gottlieb on 7/18/21.
//

import Suite
import CloudKit

public enum CKRecordChange {
	case deleted(CKRecord.ID, CKRecord.RecordType)
	case changed(CKRecord.ID, CKRecord)
	case badRecord

	var recordType: CKRecord.RecordType? {
		switch self {
		case .deleted(_, let type): return type
		case .changed(_, let record): return record.recordType
		case .badRecord: return nil
		}
	}
}

public class AsyncZoneChangesSequence: AsyncSequence {
	public typealias AsyncIterator = RecordIterator
	public typealias Element = CKRecordChange
		
	let database: CKDatabase
	let zoneIDs: [CKRecordZone.ID]
	var resultChunkSize: Int = 0
	var tokens: ChangeTokens
	
	public var changes: [CKRecordChange] = []
	public var errors: [Error] = []
	var isComplete = false
	var queryType: CKDatabase.RecordChangesQueryType
	
	init(zoneIDs: [CKRecordZone.ID], in database: CKDatabase, queryType: CKDatabase.RecordChangesQueryType = .recent, tokens: ChangeTokens = Cirrus.instance.localState.changeTokens) {
		self.database = database
		self.zoneIDs = zoneIDs
		self.queryType = queryType
		self.tokens = tokens

		if queryType == .all {
			tokens.clear()
		}
	}
	
	public func start() {
		if zoneIDs.isEmpty {
			isComplete = true
			return
		}
		run()
	}
	
	func run(cursor: CKQueryOperation.Cursor? = nil) {
		let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: zoneIDs, configurationsByRecordZoneID: tokens.tokens(for: zoneIDs))
		
		if queryType != .createdOnly {
			operation.recordWithIDWasDeletedBlock = { id, type in
				if type.isEmpty {
					self.changes.append(.badRecord)
				} else {
					self.changes.append(CKRecordChange.deleted(id, type))
				}
			}
		}
		
		operation.recordWasChangedBlock = { id, result in
			switch result {
			case .failure(let error):
				Cirrus.instance.shouldCancelAfterError(error)
				self.errors.append(error)
				
			case .success(let record):
				self.changes.append(.changed(id, record))
			}
		}
		
		operation.recordZoneFetchResultBlock = { zoneID, results in
			switch results {
			case .failure(let error):
				Cirrus.instance.shouldCancelAfterError(error)
				self.errors.append(error)
				
			case .success(let done):		// (serverChangeToken: CKServerChangeToken, clientChangeTokenData: Data?, moreComing: Bool)
				self.tokens.setChangeToken(done.serverChangeToken, for: zoneID)
				print("Zone change token: \(done.serverChangeToken)")
				if !done.moreComing { self.isComplete = true }
			}
		}
		
		operation.fetchRecordZoneChangesResultBlock = { result in
			switch result {
			case .failure(let error):
				Cirrus.instance.shouldCancelAfterError(error)
				self.errors.append(error)
				
			case .success:
				self.isComplete = true
			}
		}
		
		database.add(operation)
	}

	public struct RecordIterator: AsyncIteratorProtocol {
		var position = 0
		public mutating func next() async throws -> CKRecordChange? {
			while true {
				if let error = sequence.errors.first { throw error }
				if position < sequence.changes.count {
					position += 1
					return sequence.changes[position - 1]
				}
				
				if sequence.isComplete {
					return nil
				}
				try? await Task.sleep(nanoseconds: 1_000)
			}
		}
		
		public typealias Element = CKRecordChange
		var sequence: AsyncZoneChangesSequence
		
	}
	
	public __consuming func makeAsyncIterator() -> RecordIterator {
		RecordIterator(sequence: self)
	}
}

