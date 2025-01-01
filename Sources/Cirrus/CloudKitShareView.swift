//
//  CloudKitShareView.swift
//
//
//  Created by Ben Gottlieb on 11/15/23.
//

import Foundation
import CloudKit
import SwiftUI

#if os(iOS)
public struct CloudKitShareView: UIViewControllerRepresentable {
	let share: CKShare
	var container: CKContainer
	
	public init(share: CKShare, container: CKContainer?) {
		self.share = share
		self.container = container ?? Cirrus.container
	}

	public func makeUIViewController(context: Context) -> UICloudSharingController {
		let sharingController = UICloudSharingController(share: share, container: container)
		sharingController.availablePermissions = [.allowReadOnly, .allowPrivate]
		if share.publicPermission == .readWrite { sharingController.availablePermissions = [.allowReadWrite, .allowPrivate] }
		
		sharingController.modalPresentationStyle = .formSheet
		return sharingController
	}
	
	public func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {
		
	}
}
#endif
