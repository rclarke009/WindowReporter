//
//  JobStatus.swift
//  WindowReporter
//

import Foundation
import CoreData

enum JobStatus: String, CaseIterable {
    case newImport = "newImport"
    case inProgress = "inProgress"
    case tested = "tested"
    case reportDelivered = "reportDelivered"
    case backedUpToArchive = "backedUpToArchive"
    
    var displayName: String {
        switch self {
        case .newImport:
            return "New Import"
        case .inProgress:
            return "In Progress"
        case .tested:
            return "Tested"
        case .reportDelivered:
            return "Report Delivered"
        case .backedUpToArchive:
            return "Archived"
        }
    }
    
    var color: String {
        switch self {
        case .newImport:
            return "blue"
        case .inProgress:
            return "orange"
        case .tested:
            return "green"
        case .reportDelivered:
            return "purple"
        case .backedUpToArchive:
            return "gray"
        }
    }
    
    var icon: String {
        switch self {
        case .newImport:
            return "doc.badge.plus"
        case .inProgress:
            return "pencil.circle"
        case .tested:
            return "checkmark.circle.fill"
        case .reportDelivered:
            return "paperplane.fill"
        case .backedUpToArchive:
            return "archivebox.fill"
        }
    }
}

extension Job {
    /// Computed property to determine current job status based on job state
    var computedStatus: JobStatus {
        // Check if backed up to archive (highest priority)
        if backedUpToArchiveAt != nil {
            return .backedUpToArchive
        }
        
        // Check if report delivered
        if reportDeliveredAt != nil {
            return .reportDelivered
        }
        
        // Check if all windows are tested
        if areAllWindowsTested {
            return .tested
        }
        
        // Check if job has been edited (in progress)
        if hasBeenEdited {
            return .inProgress
        }
        
        // Default: new import
        return .newImport
    }
    
    /// Current status, preferring stored status if available, otherwise computed
    var currentStatus: JobStatus {
        if let storedStatus = jobStatus, let status = JobStatus(rawValue: storedStatus) {
            return status
        }
        return computedStatus
    }
    
    /// Update status based on current job state
    func updateStatus() {
        let newStatus = computedStatus
        jobStatus = newStatus.rawValue
    }
    
    /// Check if job has been edited (updatedAt is significantly later than createdAt)
    private var hasBeenEdited: Bool {
        guard let createdAt = createdAt, let updatedAt = updatedAt else {
            return false
        }
        
        // Consider edited if updatedAt is more than 5 seconds after createdAt
        let timeDifference = updatedAt.timeIntervalSince(createdAt)
        return timeDifference > 5.0
    }
    
    /// Check if all windows are tested (have testResult or marked as inaccessible)
    var areAllWindowsTested: Bool {
        guard let windowsSet = windows, !windowsSet.allObjects.isEmpty else {
            // No windows means not tested
            return false
        }
        
        let windowsArray = windowsSet.allObjects as? [Window] ?? []
        
        // All windows must have either a test result or be marked inaccessible
        return windowsArray.allSatisfy { window in
            window.isInaccessible || window.testResult != nil
        }
    }
    
    /// Mark report as delivered
    func markReportDelivered() {
        reportDeliveredAt = Date()
        updateStatus()
    }
    
    /// Mark as backed up to archive
    func markBackedUpToArchive() {
        backedUpToArchiveAt = Date()
        updateStatus()
    }
}
