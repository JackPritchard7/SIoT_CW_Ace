# Development of a Real-Time Tennis Stroke Classifier and Training Aid Using Inertial Sensing and Embedded Machine Learning  
**Realtime Tennis Stroke Classifier Pipeline**

The main repository for the Sensing and the Internet of Things project by Jack Pritchard.

# Abstract
The use of sensors in sports provides both performance analytics and real-time feedback to assist in technique refinement. In tennis, existing sensors are often expensive and hinder the performance properties of the racket, limiting their accessibility to players. They also require on-court usage with either a training partner or a ball machine.

This work presents the development of a wrist-worn wearable capable of real-time tennis stroke classification and training feedback using inertial sensing and embedded machine learning. The device is accompanied by a mobile app enabling data analytics and simulation of match scenarios to support technique development anytime, anywhere, without requiring court or partner availability.

Accelerometer and gyroscopic data were collected from two participants to train a two-stage classifier that first distinguishes idle motion from swings and then identifies forehand, backhand, and serve strokes. The system achieved a test accuracy of **0.99**, with perfect accuracy for the known user and **0.83** accuracy for an unseen user, and demonstrated real-time inference speeds of **8.45 ms** per stroke with reliable BLE transmission.

These results demonstrate that a low-cost wrist-worn wearable can deliver accurate, low-latency stroke analytics and provide a foundation for accessible at-home tennis training with potential future expansion to other swing-based sports.

# Project Structure
1. Time series data collection using ESP32 Dev microcontroller and MPU-6050 stored in a locally hosted instance of InfluxDB  
2. Training a machine learning classifier  
3. Real-time classification on embedded device  
4. Data upload to InfluxDB Cloud  

# File Explanations

- **Ace_ESP32_Data_Collection.ino** – collects IMU time-series data from the ESP32 and stores it in a locally hosted InfluxDB instance.  
- **Ace_Classifier_NN.ipynb** – Jupyter notebook for training and evaluating the neural network classifier.  
- **main.cpp** – handles real-time classification and BLE transmission to the mobile app.  
- **convert_to_header.py** – converts the TFLite model into a `.h` file for microcontroller deployment.  
- **export_tflite.py** – exports the trained TensorFlow model to TensorFlow Lite.  
- **ACETennis** – iOS mobile application source code.  

## Prerequisites

### Hardware
- [ESP32 Dev](https://www.amazon.co.uk/dp/B0DJPZHZ1X?ref=ppx_yo2ov_dt_b_fed_asin_title)  
- [MPU-6050 IMU Sensor](https://www.amazon.co.uk/Generic-MPU-6050-GY-521-Accelerometer-Gyroscope/dp/B0DLTZJRB3/)  

### Software
- [Python](https://www.python.org/downloads/)  
- [Visual Studio Code](https://code.visualstudio.com/)  
- [PlatformIO IDE](https://platformio.org/) extension for VS Code  

## Installation

### 1. Clone the Repository
```bash
git clone https://github.com/<your-username>/<your-repo>.git
cd <your-repo>
