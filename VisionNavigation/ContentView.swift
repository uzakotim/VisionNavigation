//
//  ContentView.swift
//  VisionNavigation
//
//  Created by Timur Uzakov on 03/12/25.
//

import SwiftUI
internal import Combine
import CoreMedia

struct ContentView: View {
    @StateObject private var navigator = VisionNavigator(targetIP: "192.168.1.4", port: 8080)
    @State private var isLandscape: Bool = UIDevice.current.orientation.isLandscape
    @State private var isRunning = false
    @StateObject private var announcer = RobotAnnouncer()
    @State private var speechTask: Task<Void, Never>? = nil
    @State private var speechIntervalSeconds: Double = 12 // adjust as desired

    var body: some View {
        ScrollView {
            GeometryReader { geometry in
                VStack(spacing: 20) {
                    Text("Optical Flow Navigation")
                        .font(.title2)
                        .padding(.top)

                    HStack {
                        Text("IP:")
                        TextField("192.168.1.4", text: $navigator.ip)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.horizontal)

                    HStack {
                        Text("Port:")
                        TextField("8080", text: $navigator.port)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.horizontal)

                    VStack {
                        Text("Speed: \(Int(navigator.speed))")
                        Slider(value: $navigator.speed, in: 0...255)
                    }
                    .padding(.horizontal)

                    Button(action: {
                        if navigator.isRunning {
                            navigator.stopNavigation()
                            stopSpeechLoop()
                        } else {
                            navigator.startNavigation()
                            startSpeechLoop()
                        }
                    }) {
                        Text(navigator.isRunning ? "Stop" : "Start")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(navigator.isRunning ? Color.red : Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .padding(.horizontal)

                    Text("Status: \(navigator.status)")
                        .padding(.bottom, 8)

                    HStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { i in
                            Text(navigator.regionStates.indices.contains(i) ? navigator.regionStates[i] : "FAR")
                                .font(.system(size: max(16, geometry.size.width * 0.035), weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.6))
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(.bottom, geometry.safeAreaInsets.bottom)
            }
            // GeometryReader takes all available height; to allow ScrollView to compute content size,
            // wrap it in a fixed minHeight using an overlay container:
            .frame(maxWidth: .infinity, minHeight: 0)
        }
        .onAppear {
            navigator.setupCamera()
        }
        .onDisappear {
            navigator.stopNavigation()
            stopSpeechLoop()
        }
    }

    private func startSpeechLoop() {
        stopSpeechLoop() // ensure only one task
        speechTask = Task.detached { [speechIntervalSeconds, announcer] in
            // Run until cancelled
            while !Task.isCancelled {
                // Speak immediately, then wait
                await MainActor.run {
                    announcer.speakRandomPhrase()
                }
                // Sleep for the interval; exit early if cancelled
                try? await Task.sleep(for: .seconds(speechIntervalSeconds))
            }
        }
    }

    private func stopSpeechLoop() {
        speechTask?.cancel()
        speechTask = nil
    }
}
