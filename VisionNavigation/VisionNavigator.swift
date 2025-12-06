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
    private let connectionQueue = DispatchQueue(label: "vision.navigator.udp")

    // Camera
    private var captureSession: AVCaptureSession?

    // Optical flow
    @Published var lastPixelBuffer: CVPixelBuffer?
    private let ciContext = CIContext()

    // Depth processing
    private let depthProcessor: DepthProcessor? = DepthProcessor()
    private var lastBufferProcessingDate: Date = .distantPast
    private let processingFPS: Double = 5.0

    // Command coalescing / rate limiting
    private var lastSentCommand: String?
    private var lastSendDate: Date = .distantPast
    private let minSendInterval: TimeInterval = 0.15

    // MARK: - Init
    init(targetIP: String, port: UInt16) {
        self.ip = targetIP
        self.port = String(port)
        super.init()
        setupConnection()
    }

    // MARK: - Public control methods for ContentView
    func startNavigation() {
        guard !isRunning else { return }
        isRunning = true
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
        sendCommand("k 0")
        log("Stopped VisionNavigator")
        updateStatus("Stopped")
    }

    // Expose for .onAppear
    func setupCamera() {
        let session = AVCaptureSession()
        session.sessionPreset = .medium

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            log("Camera error")
            updateStatus("Camera error")
            return
        }
        if session.canAddInput(input) {
            session.addInput(input)
        } else {
            log("Cannot add camera input")
            updateStatus("Camera input error")
            return
        }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera.frame.queue"))
        if session.canAddOutput(output) {
            session.addOutput(output)
        } else {
            log("Cannot add camera output")
            updateStatus("Camera output error")
            return
        }

        session.startRunning()
        captureSession = session
        updateStatus("Camera running")
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
        log("UDP connection started to \(ip):\(portValue)")
        updateStatus("Connected to \(ip):\(portValue)")
    }

    private func reconnectIfNeeded() {
        // Recreate connection with current ip/port
        udpConnection?.cancel()
        udpConnection = nil
        setupConnection()
    }

    // MARK: - Frame Processing
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isRunning else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Existing optical flow logic
//        if let last = lastPixelBuffer {
//            analyzeOpticalFlow(prev: last, curr: pixelBuffer)
//        }
        lastPixelBuffer = pixelBuffer

        // Throttled depth processing (≈5 FPS)
        let now = Date()
        if now.timeIntervalSince(lastBufferProcessingDate) >= (1.0 / processingFPS) {
            lastBufferProcessingDate = now
            if let depthProcessor = depthProcessor {
                depthProcessor.process(pixelBuffer: pixelBuffer) { [weak self] result in
                    guard let self = self, let result = result else { return }
                    // Publish to UI
                    self.depthImage = result.colorizedImage
                    self.regionStates = result.regionAverages.map { $0 < 0.5 ? "FAR" : "NEAR" }

                    // Decide and send command based on regions (parameterized + deduplicated)
                    let cmd = self.commandForRegionStates(self.regionStates)
                    self.sendCommand(cmd)
                    self.status = "sending command \(cmd)"
                }
            }
        }
    }

    // MARK: - Region-based command decision
    // Map [left, center, right] states to a command string.
    private func commandForRegionStates(_ states: [String]) -> String {
        let l = states[0], c = states[1], r = states[2]

        let turn = 180
        let forward = 90

        // Consolidated logic from original if-chain:
        if l == "NEAR" && c == "NEAR" && r == "NEAR" {
            return "q \(turn)"
        }
        if l == "FAR" && c == "FAR" && r == "FAR" {
            return "w \(forward)"
        }
        if l == "NEAR" && c == "FAR" && r == "FAR" {
            return "e \(turn)"
        }
        if l == "FAR" && c == "NEAR" && r == "FAR" {
            return "q \(turn)"
        }
        if l == "FAR" && c == "FAR" && r == "NEAR" {
            return "q \(turn)"
        }
        if l == "FAR" && c == "NEAR" && r == "NEAR" {
            return "q \(turn)"
        }
        if l == "NEAR" && c == "FAR" && r == "NEAR" {
            return "w \(forward)"
        }
        if l == "NEAR" && c == "NEAR" && r == "FAR" {
            return "e \(turn)"
        }
        return "k 0"
    }

    private func sendCommandCoalesced(_ cmd: String) {
        // Avoid sending the same command too frequently
        let now = Date()
        if cmd == lastSentCommand, now.timeIntervalSince(lastSendDate) < minSendInterval {
            return
        }
        lastSentCommand = cmd
        lastSendDate = now
        sendCommand(cmd)
    }

    // MARK: - Optical Flow
    private func analyzeOpticalFlow(prev: CVPixelBuffer, curr: CVPixelBuffer) {
        let currImage = CIImage(cvPixelBuffer: curr)
        guard let avgLeft = averageBrightness(image: currImage.cropped(to: CGRect(x: 0, y: 0, width: currImage.extent.width/2, height: currImage.extent.height))),
              let avgRight = averageBrightness(image: currImage.cropped(to: CGRect(x: currImage.extent.width/2, y: 0, width: currImage.extent.width/2, height: currImage.extent.height))) else {
            return
        }

        let diff = avgLeft - avgRight

        let threshold: Float = 0.05
        let spd = max(0, min(255, Int(speed)))

        if abs(diff) < threshold {
            sendCommandCoalesced("w \(spd)") // forward
        } else if diff > 0 { // right side obstacle
            sendCommandCoalesced("q \(spd)") // turn left
        } else { // left side obstacle
            sendCommandCoalesced("e \(spd)") // turn right
        }
    }

    private func averageBrightness(image: CIImage) -> Float? {
        let extent = image.extent
        let params: [String: Any] = [
            kCIInputImageKey: image,
            kCIInputExtentKey: CIVector(cgRect: extent)
        ]
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: params) else {
            return nil
        }
        guard let output = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(output, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)

        let r = Float(bitmap[0]) / 255.0
        let g = Float(bitmap[1]) / 255.0
        let b = Float(bitmap[2]) / 255.0
        return (r + g + b) / 3.0
    }

    // MARK: - UDP
    private func sendCommand(_ cmd: String) {
        if udpConnection == nil {
            setupConnection()
        }
        udpConnection?.send(content: cmd.data(using: .utf8), completion: .contentProcessed({ _ in }))
        log("Sent: \(cmd)")
    }

    // MARK: - Helpers
    private func log(_ msg: String) {
        DispatchQueue.main.async {
            self.onLog?(msg)
        }
    }

    private func updateStatus(_ msg: String) {
        DispatchQueue.main.async {
            self.status = msg
        }
    }
}
