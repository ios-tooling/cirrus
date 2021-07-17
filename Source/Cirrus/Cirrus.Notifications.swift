//
//  Cirrus.Notifications.swift
//  Cirrus
//
//  Created by Ben Gottlieb on 7/17/21.
//

import Foundation

public extension Cirrus {
	struct Notifications {
		public static let currentUserChanged = Notification.Name("Cirrus:currentUserChanged")			// the object will be the id of the previous user, if there was one
	}
}
