# ACE Tennis iOS App

Simple iOS app to receive tennis shot classifications from ESP32 via BLE and batch upload to InfluxDB.

## Features
- 📡 Connect to ESP32 via Bluetooth LE
- 🎾 Receive shot classifications in real-time
- 📊 Display shot statistics
- ☁️ Batch upload session data to InfluxDB when session ends

## Setup

1. Open `ACETennis.xcodeproj` in Xcode
2. Update InfluxDB credentials in `InfluxDBService.swift`
3. Build and run on your iPhone

## Requirements
- iOS 15.0+
- Xcode 14+
- iPhone with Bluetooth LE support
