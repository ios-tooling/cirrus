//
//  CKDatabaseCache.swift
//
//
//  Created by Ben Gottlieb on 6/24/23.
//

import CloudKit

public class CKDatabaseCache: ObservableObject {
	let scope: CKDatabase.Scope
	let container: CKContainerCache
	let url: URL
	
	public var records: [CKRecord.ID: WrappedCKRecord] = [:]
	
	init(scope: CKDatabase.Scope, in container: CKContainerCache) {
		self.scope = scope
		self.container = container
		self.url = container.url.appendingPathComponent(scope.name, conformingTo: .directory)
		try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
		load()
	}
	
	public func allRecords<Record: WrappedCKRecord>() -> [Record] {
		Array(records.values.filter { $0.recordType == Record.recordType }) as! [Record]
	}
	
	public func resolve<Record: WrappedCKRecord>(reference: CKRecord.Reference?) -> Record? {
		guard let reference else { return nil }
		
		return records[reference.recordID] as? Record
	}
	
	public subscript(id: CKRecord.ID) -> WrappedCKRecord? {
		get { records[id] }
		set {
			guard let newValue else {
				records.removeValue(forKey: id)
				return
			}
			
			records[id] = newValue
			save(record: newValue)
		}
	}
	
	public func cache(record: WrappedCKRecord) {
		self.records[record.recordID] = record
		save(record: record)
	}
	
	public func load(records: [CKRecord]) {
		for record in records {
			if let current = self.records[record.recordID] {
				current.merge(fromLatest: record)
				save(record: current)
			} else {
				let type = container.translator(record.recordType) ?? WrappedCKRecord.self
				
				let newRecord = type.init(record: record, in: scope.database)
				self.records[record.recordID] = newRecord
				save(record: newRecord)
			}
		}
	}
	
	func save(record: WrappedCKRecord) {
		do {
			records[record.recordID] = record
			let typeURL = url.appendingPathComponent(record.recordType, conformingTo: .directory)
			try? FileManager.default.createDirectory(at: typeURL, withIntermediateDirectories: true)
			let recordURL = typeURL.appendingPathComponent(record.recordID.recordName, conformingTo: .json)
			let data = try JSONEncoder().encode(record)
			try data.write(to: recordURL)
		} catch {
			print("Failed to save \(record): \(error)")
		}
	}
	
	func save() {
		for record in records.values {
			save(record: record)
		}
	}
	
	func load() {
		do {
			let recordTypeURLs = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
			
			for recordTypeURL in recordTypeURLs {
				let recordType = recordTypeURL.lastPathComponent
				let recordClass = container.translator(recordType) ?? WrappedCKRecord.self
				if let fileURLs = try? FileManager.default.contentsOfDirectory(at: recordTypeURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
					for fileURL in fileURLs {
						if let data = try? Data(contentsOf: fileURL) {
							let record = try JSONDecoder().decode(recordClass, from: data)
							self.records[record.recordID] = record
						}
					}
				}
			}
		} catch {
			print("Failed to load cached database \(scope.name): \(error)")
		}
	}
}
