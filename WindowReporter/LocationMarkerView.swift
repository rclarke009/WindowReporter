//
//  LocationMarkerView.swift
//  WindowReporter
//
//  macOS - Mark specimen location on overhead image (mirrors iOS LocationMarkerView).
//

import SwiftUI
import CoreData
import AppKit

struct LocationMarkerView: View {
    let window: Window
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var image: NSImage?
    @State private var markedLocation: CGPoint?
    
    private var job: Job? { window.job }
    
    var body: some View {
        VStack(spacing: 0) {
            Text("Mark Location")
                .font(.headline)
                .padding()
            
            if let image = image {
                imageView(image: image)
            } else if job?.overheadImagePath == nil {
                noOverheadPlaceholder
            } else {
                loadingPlaceholder
            }
            
            bottomButtons
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            loadImage()
            loadExistingLocation()
        }
    }
    
    private func imageView(image: NSImage) -> some View {
        GeometryReader { geometry in
            let containerSize = geometry.size
            let pixelSize = overheadImagePixelSize(image)
            let (displayRect, _) = aspectFitRect(pixelSize: pixelSize, containerSize: containerSize)
            
            ZStack(alignment: .topLeading) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: displayRect.width, height: displayRect.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        handleTap(at: location, displayRect: displayRect, pixelSize: pixelSize)
                    }
                
                if let location = markedLocation {
                    markedLocationDot(location: location, pixelSize: pixelSize, displayRect: displayRect)
                }
            }
        }
    }
    
    private func handleTap(at location: CGPoint, displayRect: CGRect, pixelSize: CGSize) {
        guard displayRect.width > 0, displayRect.height > 0, pixelSize.width > 0, pixelSize.height > 0 else { return }
        // Tap may be in container space or image-view (local) space
        let relX = location.x - displayRect.origin.x
        let relY = location.y - displayRect.origin.y
        let (localX, localY): (CGFloat, CGFloat)
        if relX >= 0, relX <= displayRect.width, relY >= 0, relY <= displayRect.height {
            localX = relX
            localY = relY
        } else if location.x >= 0, location.x <= displayRect.width, location.y >= 0, location.y <= displayRect.height {
            localX = location.x
            localY = location.y
        } else {
            print("MYDEBUG →", "Tap outside image area, ignoring")
            return
        }
        let imagePixelX = localX * pixelSize.width / displayRect.width
        let imagePixelY = localY * pixelSize.height / displayRect.height
        let imageLocation = CGPoint(x: imagePixelX, y: imagePixelY)
        print("MYDEBUG →", "Mark location at image pixel: \(imageLocation)")
        markedLocation = imageLocation
    }
    
    private func markedLocationDot(location: CGPoint, pixelSize: CGSize, displayRect: CGRect) -> some View {
        let displayX = location.x * displayRect.width / pixelSize.width
        let displayY = location.y * displayRect.height / pixelSize.height
        let viewX = displayRect.origin.x + displayX
        let viewY = displayRect.origin.y + displayY
        return Circle()
            .fill(Color.blue)
            .frame(width: 20, height: 20)
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .position(x: viewX, y: viewY)
            .allowsHitTesting(false)
    }
    
    /// Returns (rect of fitted image in container, displayed size)
    private func aspectFitRect(pixelSize: CGSize, containerSize: CGSize) -> (CGRect, CGSize) {
        guard pixelSize.width > 0, pixelSize.height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return (.zero, .zero)
        }
        let imageAspect = pixelSize.width / pixelSize.height
        let containerAspect = containerSize.width / containerSize.height
        let displayWidth: CGFloat
        let displayHeight: CGFloat
        let originX: CGFloat
        let originY: CGFloat
        if imageAspect > containerAspect {
            displayWidth = containerSize.width
            displayHeight = containerSize.width / imageAspect
            originX = 0
            originY = (containerSize.height - displayHeight) / 2
        } else {
            displayHeight = containerSize.height
            displayWidth = containerSize.height * imageAspect
            originX = (containerSize.width - displayWidth) / 2
            originY = 0
        }
        return (CGRect(x: originX, y: originY, width: displayWidth, height: displayHeight), CGSize(width: displayWidth, height: displayHeight))
    }
    
    private var noOverheadPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Overhead Image")
                .font(.title2)
            Text("Add an overhead image to this job in Job Overview first.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var loadingPlaceholder: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading overhead image...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var bottomButtons: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            
            Spacer()
            
            Button("Save") {
                saveLocation()
            }
            .disabled(markedLocation == nil)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func loadImage() {
        guard let job = job, let imagePath = job.overheadImagePath else { return }
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let imageURL = documentsDirectory.appendingPathComponent("overhead_images").appendingPathComponent(imagePath)
        guard FileManager.default.fileExists(atPath: imageURL.path),
              let loadedImage = NSImage(contentsOf: imageURL) else {
            return
        }
        image = loadedImage
    }
    
    private func loadExistingLocation() {
        if window.xPosition > 0 && window.yPosition > 0 {
            markedLocation = CGPoint(x: window.xPosition, y: window.yPosition)
        }
    }
    
    private func saveLocation() {
        guard let location = markedLocation, let job = job else { return }
        window.xPosition = Double(location.x)
        window.yPosition = Double(location.y)
        window.updatedAt = Date()
        do {
            try viewContext.save()
            NotificationCenter.default.post(name: .jobDataUpdated, object: job)
            dismiss()
        } catch {
            print("MYDEBUG →", "Error saving location: \(error)")
        }
    }
}
