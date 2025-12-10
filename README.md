# Development of a Real-Time Tennis Stroke Classifier and Training Aid Using Inertial Sensing and Embedded Machine Learning

## Realtime Tennis Stroke Classifier Pipeline

The main repository for the Sensing and the Internet of Things project by Jack Pritchard.

## Abstract

The use of sensors in sports provides both performance analytics and real-time feedback to assist in technique refinement. In tennis, existing sensors are often expensive and hinder the performance properties of the racket, limiting their accessibility to players. They also require on-court usage with either a training partner or a ball machine. 

This work presents the development of a wrist-worn wearable capable of real-time tennis stroke classification and training feedback using inertial sensing and embedded machine learning. The device is accompanied by a mobile app enabling data analytics and simulation of match scenarios to support technique development anytime, anywhere, without requiring court or partner availability. 

Accelerometer and gyroscopic data were collected from two participants to train a two-stage classifier that first distinguishes idle motion from swings and then identifies forehand, backhand, and serve strokes. The system achieved a test accuracy of 0.99, with perfect accuracy for the known user and 0.83 accuracy for an unseen user, and demonstrated real-time inference speeds of 8.45 ms per stroke with reliable BLE transmission. 

These results demonstrate that a low-cost wrist-worn wearable can deliver accurate, low-latency stroke analytics and provide a foundation for accessible at-home tennis training with potential future expansion to other swing-based sports.

## Project Structure

- Time series data collection using ESP32 Dev microcontroller and MPU-6050 stored in a locally hosted instance of InfluxDB
- Training a machine learning classifier
- Real-time classification on embedded device
- Data upload to InfluxDB Cloud

## File Explanations

- **Ace_ESP32_Data_Collection.ino** – collects IMU time-series data from the ESP32 and stores it in a locally hosted InfluxDB instance.
- **Ace_Classifier_NN.ipynb** – Jupyter notebook for training and evaluating the neural network classifier.
- **main.cpp** – handles real-time classification and BLE transmission to the mobile app.
- **convert_to_header.py** – converts the TFLite model into a .h file for microcontroller deployment.
- **export_tflite.py** – exports the trained TensorFlow model to TensorFlow Lite.
- **ACETennis** – iOS mobile application source code.

## Prerequisites

### Hardware
- ESP32 Dev
- MPU-6050 IMU Sensor

### Software
- Python
- Visual Studio Code
- PlatformIO IDE extension for VS Code

## Installation

### 1. Clone the Repository
```bash
git clone https://github.com/<JackPritchard7/<SIoT_CW_Ace>.git
cd <SIoT_CW_Ace>
```

### 2. Install Python Dependencies
```bash
pip install -r requirements.txt
```

### 3. Set up PlatformIO in VS Code
- Open VS Code
- Install the PlatformIO IDE extension
- Open the project folder
- PlatformIO will automatically load the project environments
- Allow PlatformIO to install toolchains and frameworks

### 4. Configure ESP32
- Connect your ESP32 Dev board
- Select the correct COM port in PlatformIO
- Upload firmware:
```bash
pio run --target upload
```

## Required Manual Setup Before Running

### File Directory Updates
- Open `Ace_Classifier_NN.ipynb` and paste your file directory where indicated.
- Open `export_tflite.py` and paste your file directory where indicated.
- Open `convert_to_header.py` and paste your file directory where indicated.

### Wi-Fi Credentials
- Open `Ace_ESP32_Data_Collection.ino` and paste your Wi-Fi credentials where indicated.

### InfluxDB Cloud Credentials
- Open `InfluxBService.swift` and paste your InfluxDB Cloud credentials where indicated.

### InfluxDB Local Credentials
- Open `Ace_ESP32_Data_Collection.ino` and paste your local InfluxDB credentials where indicated.

## Pipeline

### 1. Data Collection
1. Open `Ace_ESP32_Data_Collection.ino`
2. Fill out Wi-Fi credentials
3. Fill out InfluxDB configuration
4. Upload to ESP32
5. Power the ESP32 and begin collecting data
6. When finished, download the CSV files
7. Rename and organise your data into:
   - Forehand
   - Backhand
   - Serve
   - Idle

### 2. Training Classifier
1. Open `Ace_Classifier_NN.ipynb` and run all cells
2. Run `export_tflite.py`
3. Run `convert_to_header.py`

### 3. BLE Classifier
1. Open `main.cpp`
2. Update normalisation parameters
3. Select the correct sample rate and window size
4. Upload to ESP32
5. Open the iOS app and connect to the ESP32
6. Perform shots to receive real-time classifications
7. At the end of the session, upload data to InfluxDB Cloud

### 4. InfluxDB Cloud
1. Open InfluxDB Cloud
2. Select your bucket
3. Select your measurement
4. Download stored data as needed

### 5. Happy Swinging (Not literally!)
Develop your technique, gain insights into your strokes, and test your swing tempo in Game Mode.
