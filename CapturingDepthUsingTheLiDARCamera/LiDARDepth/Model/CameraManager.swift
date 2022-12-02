/*
See LICENSE folder for this sample’s licensing information.

Abstract:
An object that connects the CameraController and the views.
*/

import Foundation
import SwiftUI
import Combine
import simd
import AVFoundation

class CameraManager: ObservableObject {
    
    let controller: CameraController
    var session: AVCaptureSession { controller.captureSession }
    
    init() {
        // Create an object to store the captured data for the views to present.
        controller = CameraController()
        controller.startStream()
    }
    
    func lockConfig() {
        controller.lockConfig()
    }
   
}
