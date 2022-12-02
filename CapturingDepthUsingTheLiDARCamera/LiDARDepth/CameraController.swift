/*
See LICENSE folder for this sample’s licensing information.

Abstract:
An object that configures and manages the capture pipeline to stream video and LiDAR depth data.
*/

import Foundation
import AVFoundation
import CoreImage

class CameraController: NSObject, ObservableObject {
    
    enum ConfigurationError: Error {
        case lidarDeviceUnavailable
        case requiredFormatUnavailable
    }
    
    private let preferredWidthResolution = 1920
    
    private let videoQueue = DispatchQueue(label: "com.example.apple-samplecode.VideoQueue", qos: .userInteractive)
    
    private(set) var captureSession: AVCaptureSession!
    
    private var depthDataOutput: AVCaptureDepthDataOutput!
    private var videoDataOutput: AVCaptureVideoDataOutput!
    private var outputVideoSync: AVCaptureDataOutputSynchronizer!
        
    var doTest = false
    var startTimeStamp = CMTime.zero
    var startTime: Double = 0
    var counter = 0
    
    var preferFPS: Int32 = 60
    
    private var device: AVCaptureDevice!
    
    override init() {
        super.init()
        
        do {
            try setupSession()
        } catch {
            fatalError("Unable to configure the capture session.")
        }
    }
    
    private func setupSession() throws {
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .inputPriority

        // Configure the capture session.
        captureSession.beginConfiguration()
        
        try setupCaptureInput()
        setupCaptureOutputs()
        
        // Finalize capture session configuration.
        captureSession.commitConfiguration()
        
        try device.lockForConfiguration()
        device.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: preferFPS)
        device.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: preferFPS)
        device.unlockForConfiguration()
        
        doTest = true
        startTimeStamp = .zero
    }
    
    private func setupCaptureInput() throws {
        // Look up the LiDAR camera.
        guard let device = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) else {
            throw ConfigurationError.lidarDeviceUnavailable
        }
        self.device = device
        // Find a match that outputs video data in the format the app's custom Metal views require.
        guard let format = (device.formats.last { format in
            format.formatDescription.dimensions.width == preferredWidthResolution &&
            format.videoSupportedFrameRateRanges.first!.maxFrameRate == Double(preferFPS) &&
            format.formatDescription.mediaSubType.rawValue == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange &&
            !format.supportedDepthDataFormats.isEmpty
        }) else {
            throw ConfigurationError.requiredFormatUnavailable
        }
        
        // Find a match that outputs depth data in the format the app's custom Metal views require.
        guard let depthFormat = (format.supportedDepthDataFormats.last { depthFormat in
            depthFormat.formatDescription.mediaSubType.rawValue == kCVPixelFormatType_DepthFloat16
        }) else {
            throw ConfigurationError.requiredFormatUnavailable
        }
        
        // Begin the device configuration.
        try device.lockForConfiguration()

        // Configure the device and depth formats.
        device.activeFormat = format
        device.activeDepthDataFormat = depthFormat

        // Finish the device configuration.
        device.unlockForConfiguration()
        
        print("Selected video format: \(device.activeFormat)")
        print("Selected depth format: \(String(describing: device.activeDepthDataFormat))")
        
        // Add a device input to the capture session.
        let deviceInput = try AVCaptureDeviceInput(device: device)
        captureSession.addInput(deviceInput)
    }
    
    private func setupCaptureOutputs() {
        // Create an object to output video sample buffers.
        videoDataOutput = AVCaptureVideoDataOutput()
        captureSession.addOutput(videoDataOutput)
        
        // Create an object to output depth data.
        depthDataOutput = AVCaptureDepthDataOutput()
        captureSession.addOutput(depthDataOutput)

        // Create an object to synchronize the delivery of depth and video data.
        outputVideoSync = AVCaptureDataOutputSynchronizer(dataOutputs: [depthDataOutput, videoDataOutput])
        outputVideoSync.setDelegate(self, queue: videoQueue)

        // Enable camera intrinsics matrix delivery.
        guard let outputConnection = videoDataOutput.connection(with: .video) else { return }
        if outputConnection.isCameraIntrinsicMatrixDeliverySupported {
            outputConnection.isCameraIntrinsicMatrixDeliveryEnabled = true
        }
    }
    
    func lockConfig() {
        doTest = false
        do {
            try device.lockForConfiguration()
            device.setFocusModeLocked(lensPosition: device.lensPosition) {_ in
                self.doTest = true
                self.startTimeStamp = .zero
            }
            device.setExposureModeCustom(duration: device.exposureDuration, iso: device.iso)
            device.unlockForConfiguration()
        } catch {}
    }
    
    func startStream() {
        captureSession.startRunning()
    }
    
    func stopStream() {
        captureSession.stopRunning()
    }
}

// MARK: Output Synchronizer Delegate
extension CameraController: AVCaptureDataOutputSynchronizerDelegate {
    
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer,
                                didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        
        if doTest {
            if let syncedVideoData = synchronizedDataCollection.synchronizedData(for: videoDataOutput) as? AVCaptureSynchronizedSampleBufferData {
                let timeStamp = syncedVideoData.sampleBuffer.presentationTimeStamp
                let testTime:Double = 60
                if startTimeStamp == .zero {
                    startTimeStamp = timeStamp
                    startTime = Date().timeIntervalSince1970
                    counter = 0
                }
                
                if (timeStamp - startTimeStamp).seconds >= testTime {
                    print("xxxxxxx \(counter) frames took \((timeStamp - startTimeStamp).seconds * 1000) ms in PTS; expected \(testTime * 1000) ms; real elapsed time: \((Date().timeIntervalSince1970 - startTime) * 1000) ms")
                    startTimeStamp = timeStamp
                    startTime = Date().timeIntervalSince1970
                    counter = 0
                }
                counter += 1
            }
        }
    }
}
