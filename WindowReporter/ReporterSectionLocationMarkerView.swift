//
//  ReporterSectionLocationMarkerView.swift
//  WindowReporter
//
//  Tap overhead image to set specimen section dot (NSImage / PDF coordinates).
//

import SwiftUI
import CoreData
import AppKit

struct ReporterSectionLocationMarkerView: View {
    let section: SpecimenSection
    let job: Job
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @State private var image: NSImage?
    @State private var markedLocation: CGPoint?
    @State private var isLoadingImage = true

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    Color(NSColor.windowBackgroundColor)

                    if let img = image {
                        sectionMarkerContent(img: img, containerSize: geometry.size)
                    } else if isLoadingImage {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "photo")
                                .font(.system(size: 50))
                                .foregroundColor(.secondary)
                            Text("No overhead image")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Mark location")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveMarkedLocation()
                        dismiss()
                    }
                    .disabled(markedLocation == nil)
                }
            }
            .onAppear {
                isLoadingImage = true
                loadOverheadImage()
                if section.xPosition != 0 || section.yPosition != 0 {
                    markedLocation = CGPoint(x: section.xPosition, y: section.yPosition)
                }
            }
        }
    }

    private func sectionMarkerContent(img: NSImage, containerSize: CGSize) -> some View {
        let size = overheadImagePixelSize(img)
        return ZStack {
            Image(nsImage: img)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { location in
                    let coord = slmViewToImage(viewPoint: location, containerSize: containerSize, originalImageSize: size)
                    print("MYDEBUG →", "SectionLocationMarker tap: view=\(location), image=\(coord)")
                    markedLocation = coord
                }

            if let loc = markedLocation {
                let viewPt = slmImageToView(imagePoint: loc, containerSize: containerSize, originalImageSize: size)
                Circle()
                    .fill(Color.blue)
                    .frame(width: 20, height: 20)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .position(viewPt)
            }
        }
    }

    private func slmViewToImage(viewPoint: CGPoint, containerSize: CGSize, originalImageSize: CGSize) -> CGPoint {
        let (dw, dh, xOff, yOff) = slmDisplayedFrame(containerSize: containerSize, originalImageSize: originalImageSize)
        guard dw > 0, dh > 0 else { return .zero }
        return CGPoint(
            x: (viewPoint.x - xOff) * originalImageSize.width / dw,
            y: (viewPoint.y - yOff) * originalImageSize.height / dh
        )
    }

    private func slmImageToView(imagePoint: CGPoint, containerSize: CGSize, originalImageSize: CGSize) -> CGPoint {
        let (dw, dh, xOff, yOff) = slmDisplayedFrame(containerSize: containerSize, originalImageSize: originalImageSize)
        guard originalImageSize.width > 0, originalImageSize.height > 0 else { return .zero }
        return CGPoint(
            x: imagePoint.x * dw / originalImageSize.width + xOff,
            y: imagePoint.y * dh / originalImageSize.height + yOff
        )
    }

    private func slmDisplayedFrame(containerSize: CGSize, originalImageSize: CGSize) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        guard containerSize.width > 0, containerSize.height > 0,
              originalImageSize.width > 0, originalImageSize.height > 0 else {
            return (0, 0, 0, 0)
        }
        let imgAspect = originalImageSize.width / originalImageSize.height
        let ctrAspect = containerSize.width / containerSize.height
        if imgAspect > ctrAspect {
            let w = containerSize.width
            let h = w / imgAspect
            return (w, h, 0, (containerSize.height - h) / 2)
        } else {
            let h = containerSize.height
            let w = h * imgAspect
            return (w, h, (containerSize.width - w) / 2, 0)
        }
    }

    private func loadOverheadImage() {
        defer { isLoadingImage = false }
        guard let path = job.overheadImagePath, !path.isEmpty else {
            image = nil
            return
        }
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = documentsDirectory.appendingPathComponent("overhead_images").appendingPathComponent(path)
        if FileManager.default.fileExists(atPath: url.path) {
            image = NSImage(contentsOfFile: url.path)
        }
    }

    private func saveMarkedLocation() {
        guard let loc = markedLocation else { return }
        section.xPosition = Double(loc.x)
        section.yPosition = Double(loc.y)
        section.updatedAt = Date()
        do {
            try viewContext.save()
            print("MYDEBUG →", "Section location saved: \(loc)")
            if let job = section.job {
                NotificationCenter.default.post(name: .jobDataUpdated, object: job)
            }
        } catch {
            print("MYDEBUG →", "Section location save failed: \(error)")
        }
    }
}
