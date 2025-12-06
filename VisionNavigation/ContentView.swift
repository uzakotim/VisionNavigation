//
//  ContentView.swift
//  VisionNavigation
//
//  Created by Timur Uzakov on 03/12/25.
//

import SwiftUI
internal import Combine
import CoreMedia
import AVFoundation

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var navigator = VisionNavigator(targetIP: "192.168.1.4", port: 8080)
    @State private var isLandscape: Bool = UIDevice.current.orientation.isLandscape
    @State private var isRunning = false
    @StateObject private var announcer = RobotAnnouncer()
    @State private var speechTask: Task<Void, Never>? = nil
    @State private var speechIntervalSeconds: Double = 12 // adjust as desired

    // Debounce reconnection when user edits IP/port fields
    @State private var ipCancellable: AnyCancellable?
    @State private var portCancellable: AnyCancellable?

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
                            .keyboardType(.numbersAndPunctuation)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal)

                    HStack {
                        Text("Port:")
                        TextField("8080", text: $navigator.port)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
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
                            announcer.stopAllSpeech()
                            announcer.deactivateAudioSession()
                        } else {
                            navigator.startNavigation()
                            announcer.activateAudioSessionIfNeeded()
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
            .frame(maxWidth: .infinity, minHeight: 0)
        }
        .onAppear {
            navigator.prepareForUse()
            setupDebounce()
        }
        .onDisappear {
            navigator.stopNavigation()
            stopSpeechLoop()
            announcer.stopAllSpeech()
            announcer.deactivateAudioSession()
            ipCancellable?.cancel()
            portCancellable?.cancel()
        }
        .onChange(of: scenePhase) { old, newPhase in
            switch newPhase {
            case .active:
                navigator.appBecameActive()
                announcer.activateAudioSessionIfNeeded()
                if navigator.isRunning {
                    startSpeechLoop()
                }
            case .inactive, .background:
                // Pause heavy work when not active
                navigator.appWentToBackground()
                stopSpeechLoop()
                announcer.stopAllSpeech()
                announcer.deactivateAudioSession()
            @unknown default:
                break
            }
        }
    }

    private func setupDebounce() {
        // Debounce changes to IP/port to avoid reconnect storms while typing
        ipCancellable = navigator.$ip
            .removeDuplicates()
            .debounce(for: .milliseconds(600), scheduler: RunLoop.main)
            .sink { [weak navigator] _ in
                navigator?.reconnectIfNeeded()
            }

        portCancellable = navigator.$port
            .removeDuplicates()
            .debounce(for: .milliseconds(600), scheduler: RunLoop.main)
            .sink { [weak navigator] _ in
                navigator?.reconnectIfNeeded()
            }
    }

    private func startSpeechLoop() {
        stopSpeechLoop() // ensure only one task
        speechTask = Task.detached { [speechIntervalSeconds, announcer] in
            while !Task.isCancelled {
                // Respect Low Power Mode
                if ProcessInfo.processInfo.isLowPowerModeEnabled {
                    // Speak less frequently or skip entirely
                    try? await Task.sleep(for: .seconds(max(30, speechIntervalSeconds * 2)))
                    continue
                }

                await MainActor.run {
                    // Only speak if session is active and not currently speaking
                    announcer.activateAudioSessionIfNeeded()
                    announcer.speakRandomPhrase()
                }
                try? await Task.sleep(for: .seconds(speechIntervalSeconds))
            }
        }
    }

    private func stopSpeechLoop() {
        speechTask?.cancel()
        speechTask = nil
    }
}
