//
//  AppNotifications.swift
//  WindowReporter
//
//  Shared notification names used by the app (included in both WindowReporter and BetaWindowReporter targets).
//

import Foundation

extension Notification.Name {
    static let createNewJob = Notification.Name("createNewJob")
    static let newJobCreated = Notification.Name("newJobCreated")
    static let jobDataUpdated = Notification.Name("jobDataUpdated")
}
