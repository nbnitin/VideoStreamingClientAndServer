//
//  VideoCapture.swift
//  VideoStreamingClient
//
//  Created by Nitin Bhatia on 07/10/22.
//

import Foundation
import AVFoundation

/// Absract: An facade Object configuring AVCaptureSession and managing it.
///
/// Its primary rules are to configure AVCaptureSession and
/// set delegate which should handle raw video output data
class VideoCaptureManager {
        
    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    private enum ConfigurationError: Error {
        case cannotAddInput
        case cannotAddOutput
        case defaultDeviceNotExist
    }
    
    // MARK: - dependencies
    
    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    
    // MARK: - DispatchQueues to make the most of multithreading
    
    private let sessionQueue = DispatchQueue(label: "session.queue")
    private let videoOutputQueue = DispatchQueue(label: "video.output.queue")
    
    // MARK: - init
    
    private var setupResult: SessionSetupResult = .success
    
    //All right. We’re now ready to set up AVCaptureSession. Add following code in the initializer of VideoCaptureManager to automatically set up AVCaptureSession when it is initialized.
    init() {
        sessionQueue.async {
            self.requestCameraAuthorizationIfNeeded()
        }
    
        sessionQueue.async {
            self.configureSession()
        }
        
        sessionQueue.async {
            self.startSessionIfPossible()
        }
    }
    
    // MARK: - helper methods
    //Note that we have a serial queue called ‘sessionQueue’ because we don’t want to block main queue while configuring AVCaptureSession. ‘videoOutputQueue’ will be using on which to handle captured data output. And error and result type will help us to handle configure result.
    
    //First thing we need to do is request camera usage authorization to the user.
    
    private func requestCameraAuthorizationIfNeeded() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            // we suspend the queue here and request access because
            // if the authorization is not granted, we always fail to configure AVCaptureSession
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                if !granted {
                    self.setupResult = .notAuthorized
                }
                self.sessionQueue.resume()
            })
        default:
            setupResult = .notAuthorized
        }
    }
    
    //Put the processes that add input and output together in the method named ‘configureSession’ and we need a method to let the AVCaptureSession run.
    private func configureSession() {
        if setupResult != .success {
            return
        }
        
        session.beginConfiguration()
        
        if session.canSetSessionPreset(.iFrame1280x720) {
            session.sessionPreset = .iFrame1280x720
        }
        
        do {
            try addVideoDeviceInputToSession()
            try addVideoOutputToSession()
            
            if let connection = session.connections.first {
                connection.videoOrientation = .portrait
            }
        } catch {
            print("error ocurred : \(error.localizedDescription)")
            return
        }
        
        session.commitConfiguration()
    }
    
    //Next, we need to add AVCaptureDevice and AVCaptureOutput to AVCaptureSession so that AVCaptureDevice and AVCaptureOutput can be connected. It’ll be operated in following methods.
    private func addVideoDeviceInputToSession() throws {
        do {
            var defaultVideoDevice: AVCaptureDevice?
            
            // camera devices you can use vary depending on which iPhone you are
            // using so we want to
            if let dualCameraDevice = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
                defaultVideoDevice = dualCameraDevice
            } else if let dualWideCameraDevice = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
                defaultVideoDevice = dualWideCameraDevice
            } else if let backCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                defaultVideoDevice = backCameraDevice
            } else if let frontCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
                defaultVideoDevice = frontCameraDevice
            }
            
            guard let videoDevice = defaultVideoDevice else {
                print("Default video device is unavailable.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                
                throw ConfigurationError.defaultDeviceNotExist
            }
            
            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            
            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
            } else {
                setupResult = .configurationFailed
                session.commitConfiguration()
                
                throw ConfigurationError.cannotAddInput
            }
        } catch {
            setupResult = .configurationFailed
            session.commitConfiguration()
            
            throw error
        }
    }

    private func addVideoOutputToSession() throws {
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        } else {
            setupResult = .configurationFailed
            session.commitConfiguration()
            
            throw ConfigurationError.cannotAddOutput
        }
    }
    
   
    private func startSessionIfPossible() {
        switch self.setupResult {
        case .success:
            session.startRunning()
        case .notAuthorized:
            print("camera usage not authorized")
        case .configurationFailed:
            print("configuration failed")
        }
    }
    
    // MARK: - Delegate handling video output data
    //And last, we need interface to set the object which will receive raw video data.
    // VideoOutputDelegate recieves sequence of raw CMSampleBuffers
    func setVideoOutputDelegate(with delegate: AVCaptureVideoDataOutputSampleBufferDelegate) {
        videoOutput.setSampleBufferDelegate(delegate, queue: videoOutputQueue)
    }
}

