//
//  ContentView.swift
//  VisionNavigation
//
//  Created by Timur Uzakov on 03/12/25.
//

import SwiftUI


struct ContentView: View {
    @StateObject private var navigator = VisionNavigator(targetIP: "192.168.1.16", port: 8080)

    var body: some View {
        VStack(spacing: 20) {
            Text("Optical Flow Navigation")
                .font(.title2)
                .padding(.top)

            HStack {
                Text("IP:")
                TextField("192.168.1.4", text: $navigator.ip)
                    .textFieldStyle(.roundedBorder)
            }.padding(.horizontal)

            HStack {
                Text("Port:")
                TextField("8888", text: $navigator.port)
                    .textFieldStyle(.roundedBorder)
            }.padding(.horizontal)

            VStack {
                Text("Speed: \(Int(navigator.speed))")
                Slider(value: $navigator.speed, in: 0...255)
            }.padding(.horizontal)

            Button(action: {
                if navigator.isRunning {
                    navigator.stopNavigation()
                } else {
                    navigator.startNavigation()
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
                .padding()

            Spacer()
        }
        .onAppear {
            navigator.setupCamera()
        }
    }
}
