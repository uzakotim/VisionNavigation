//
//  VisionNavigator.swift
//  VisionNavigation
//
//  Created by Timur Uzakov on 03/12/25.
//

import Foundation
import UIKit
import AVFoundation
import CoreImage
import Network
import SwiftUI
internal import Combine

@MainActor
class VisionNavigator: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    // MARK: - Published properties for UI binding
    @Published var ip: String
    @Published var port: String
    @Published var speed: Double = 150
    @Published var isRunning: Bool = false
    @Published var status: String = "Idle"

    // Depth output for UI
    @Published var depthImage: UIImage? = nil
    @Published var regionStates: [String] = ["FAR", "FAR", "FAR"]

    // MARK: - Public API
    var onLog: ((String) -> Void)?

    // Networking
    private var udpConnection: NWConnection?
    private let connectionQueue = DispatchQueue(label: "vision.navigator.udp", qos: .utility)

    // Camera
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var cameraQueue = DispatchQueue(label: "camera.frame.queue", qos: .utility)

    // Optical flow
    @Published var lastPixelBuffer: CVPixelBuffer?
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // Depth processing
    private let depthProcessor: DepthProcessor? = DepthProcessor()
    private var lastBufferProcessingDate: Date = .distantPast
    private var processingFPS: Double = 10.0

    // Command coalescing / rate limiting
    private var lastSentCommand: String?
    private var lastSendDate: Date = .distantPast
    private let minSendInterval: TimeInterval = 0.15

    // Frame-skipping for command sending
    private var frameCounter: Int = 0
    var frameSkipModulo: Int = 2 // send on every Nth processed frame

    // Thermal / power state tracking
    private var thermalObserver: NSObjectProtocol?

    // MARK: - Init
    init(targetIP: String, port: UInt16) {
        self.ip = targetIP
        self.port = String(port)
        super.init()
        setupConnection()
        observeThermal()
        adaptForPowerAndThermals()
    }

    deinit {
        if let thermalObserver { NotificationCenter.default.removeObserver(thermalObserver) }
    }

    // MARK: - Lifecycle hooks
    func prepareForUse() {
        // Pre-warm connection; camera starts only when running
        setupConnection()
    }

    func appBecameActive() {
        adaptForPowerAndThermals()
        if isRunning, captureSession == nil || !(captureSession?.isRunning ?? false) {
            setupCamera()
        }
    }

    func appWentToBackground() {
        // Stop heavy work immediately
        captureSession?.stopRunning()
        captureSession = nil
        videoOutput = nil
        depthImage = nil
    }

    // MARK: - Public control methods for ContentView
    func startNavigation() {
        guard !isRunning else { return }
        isRunning = true
        frameCounter = 0
        setupCamera()
        sendCommand("k 0") // ensure robot is stopped initially
        log("Started VisionNavigator")
        updateStatus("Running")
    }

    func stopNavigation() {
        guard isRunning else { return }
        isRunning = false
        captureSession?.stopRunning()
        captureSession = nil
        videoOutput = nil
        lastPixelBuffer = nil
        depthImage = nil
        sendCommand("k 0")
        log("Stopped VisionNavigator")
        updateStatus("Stopped")
    }

    // MARK: - Camera
    func setupCamera() {
        // Configure once per start; adapt preset by power/thermal state
        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = capturePresetForCurrentState()

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            log("Camera error")
            updateStatus("Camera error")
            session.commitConfiguration()
            return
        }
        if session.canAddInput(input) { session.addInput(input) } else {
            log("Cannot add camera input")
            updateStatus("Camera input error")
            session.commitConfiguration()
            return
        }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: cameraQueue)
        if session.canAddOutput(output) { session.addOutput(output) } else {
            log("Cannot add camera output")
            updateStatus("Camera output error")
            session.commitConfiguration()
            return
        }

        // Limit frame rate to reduce energy
        do {
            try device.lockForConfiguration()
            if device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.maxFrameRate >= 15 }) {
                device.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: 15) // ~15 fps
                device.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: 15)
            }
            device.unlockForConfiguration()
        } catch {
            log("Frame rate config error: \(error)")
        }

        session.commitConfiguration()
        session.startRunning()

        captureSession = session
        videoOutput = output
        updateStatus("Camera running")
    }

    private func capturePresetForCurrentState() -> AVCaptureSession.Preset {
        // Prefer lower resolutions on Low Power Mode or high thermal states
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let thermal = ProcessInfo.processInfo.thermalState
        if lowPower || thermal == .serious || thermal == .critical {
            return .low
        } else {
            // Default to medium to save energy vs. high
            return .medium
        }
    }

    private func observeThermal() {
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.adaptForPowerAndThermals()
        }
    }

    private func adaptForPowerAndThermals() {
        // Adjust processing FPS dynamically
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        switch ProcessInfo.processInfo.thermalState {
        case .nominal, .fair:
            processingFPS = lowPower ? 3.0 : 5.0
        case .serious:
            processingFPS = 2.0
        case .critical:
            processingFPS = 1.0
        @unknown default:
            processingFPS = 3.0
        }

        // If session is running, consider lowering preset/frame rate when state worsens
        if let session = captureSession, session.isRunning {
            let desiredPreset = capturePresetForCurrentState()
            if session.sessionPreset != desiredPreset {
                session.beginConfiguration()
                if session.canSetSessionPreset(desiredPreset) {
                    session.sessionPreset = desiredPreset
                }
                session.commitConfiguration()
            }
        }
    }

    // MARK: - NWConnection setup/update
    private func setupConnection() {
        guard let portValue = UInt16(port) else {
            log("Invalid port: \(port)")
            updateStatus("Invalid port")
            return
        }
        let connection = NWConnection(host: NWEndpoint.Host(ip), port: NWEndpoint.Port(integerLiteral: portValue), using: .udp)
        udpConnection = connection
        connection.start(queue: connectionQueue)
        updateStatus("Connected to \(ip):\(portValue)")
    }

    func reconnectIfNeeded() {
        // Recreate connection with current ip/port
        udpConnection?.cancel()
        udpConnection = nil
        setupConnection()
    }

    // MARK: - Frame Processing
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // This delegate is called on cameraQueue (background). Hop to main actor for state changes.
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        Task { @MainActor in
            // publish on main
            self.lastPixelBuffer = pixelBuffer
        }

        // Throttled depth processing with dynamic FPS
        let now = Date()
        // Read processingFPS/lastBufferProcessingDate safely by hopping to main to check/update them
        Task { @MainActor in
            let interval = 1.0 / max(1.0, self.processingFPS)
            if now.timeIntervalSince(self.lastBufferProcessingDate) >= interval {
                self.lastBufferProcessingDate = now
                if let depthProcessor = self.depthProcessor {
                    // DepthProcessor calls completion on main already
                    depthProcessor.process(pixelBuffer: pixelBuffer) { [weak self] result in
                        guard let self = self, let result = result else { return }
                        // We are on main (DepthProcessor completes on main), and class is @MainActor
                        self.depthImage = result.colorizedImage
                        self.regionStates = result.regionAverages.map { $0 < 0.4 ? "FAR" : "NEAR" }

                        // Increment processed-frame counter and send only every Nth frame
                        self.frameCounter &+= 1
                        if self.frameSkipModulo <= 1 || (self.frameCounter % self.frameSkipModulo == 0) {
                            let cmd = self.commandForRegionStates(self.regionStates)
                            self.sendCommandCoalesced(cmd)
                            self.updateStatus("sending command \(cmd)")
                        } else {
                            // Optionally update status without sending
                            self.updateStatus("skipping frame \(self.frameCounter % self.frameSkipModulo)/\(self.frameSkipModulo)")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Region-based command decision
    private func commandForRegionStates(_ states: [String]) -> String {
        let l = states[0], c = states[1], r = states[2]

        let turn = 180
        let forward = 90

        if l == "NEAR" && c == "NEAR" && r == "NEAR" { return "q \(turn)" }
        if l == "FAR" && c == "FAR" && r == "FAR" { return "w \(forward)" }
        if l == "NEAR" && c == "FAR" && r == "FAR" { return "e \(turn)" }
        if l == "FAR" && c == "NEAR" && r == "FAR" { return "q \(turn)" }
        if l == "FAR" && c == "FAR" && r == "NEAR" { return "q \(turn)" }
        if l == "FAR" && c == "NEAR" && r == "NEAR" { return "q \(turn)" }
        if l == "NEAR" && c == "FAR" && r == "NEAR" { return "w \(forward)" }
        if l == "NEAR" && c == "NEAR" && r == "FAR" { return "e \(turn)" }
        return "k 0"
    }

    private func sendCommandCoalesced(_ cmd: String) {
        let now = Date()
        if cmd == lastSentCommand, now.timeIntervalSince(lastSendDate) < minSendInterval {
            return
        }
        lastSentCommand = cmd
        lastSendDate = now
        sendCommand(cmd)
    }

    // MARK: - UDP
    private func sendCommand(_ cmd: String) {
        guard let connection = udpConnection else {
            setupConnection()
            guard let connection = udpConnection else { return }
            connection.send(content: cmd.data(using: .utf8), completion: .contentProcessed({ _ in }))
            return
        }
        connection.send(content: cmd.data(using: .utf8), completion: .contentProcessed({ _ in }))
        // Avoid noisy logs to reduce console overhead and energy
        // log("Sent: \(cmd)")
    }

    // MARK: - Helpers
    private func log(_ msg: String) {
        DispatchQueue.main.async {
            self.onLog?(msg)
        }
    }

    private func updateStatus(_ msg: String) {
        self.status = msg
    }
}

