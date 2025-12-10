# Development of a Real-Time Tennis Stroke Classifier and Training Aid Using Inertial Sensing and Embedded Machine Learning Realtime Tennis Stroke Classifier Pipeline
The main repository for Sensing and the Internet of Things project, by Jack Pritchad.

# Abstract
The use of sensors in sports provide both perfor mance analytics and real-time feedback to assist in technique refinement. In tennis, existing sensors are often expensive and hinder the performance properties of the racket limiting their accessibility to players. They also require on court usage, with either a training partner or a ball machine. This work presents the development of a wrist worn wearable capable of real-time tennis stroke classification and training feedback using inertial sensing and embedded machine learning. The device will be accompanied by a mobile app which facilitates data analytics and simulation of a match scenario to develop and refine technique anytime, anywhere without depending on court and partner availability. Accelerometer and gyroscopic data were collected from two participant to train a two-stage classifier that first distinguishes idle motion from swings and then identifies forehand, backhand, and serve strokes. The system achieved a test accuracy of 0.99, with perfect accuracy for the known user and 0.83 accuracy for an unseen user, and demonstrated real time inference speeds of 8.45 ms per stroke with reliable BLE transmission. These results show that a low cost wrist worn wearable can deliver accurate, low latency stroke analytics and provide a foundation for accessible at home tennis training with the potential future expansion to other swing based sports.

# Project Structure
1. Time series data collection using ESP32 DEV microcontroller and MPU-6050 stored in a locally hosted instance of InfluxDB
2. Training a Machine Learning Classifier
3. Real-time Classification
4. Data Upload to InfluxDB Cloud


# File Explanations

- **Ace_ESP32_Data_Collection.ino** – collects time-series IMU data from the ESP32 and stores in a locally hosted InfluxDB instance.
- **Ace_Classifier_NN.ipynb** – notebook for training and evaluating the neural network classifier.
- **main.cpp** – real-time classification and BLE transmission.
- **convert_to_header.py** – converts TFLite model into C header format for microcontroller deployment.
- **export_tflite.py** – exports trained model to TensorFlow Lite format.
- **ACETennis** – mobile app source code.

## Prerequisites
- **Hardware:**
  - [ESP32 DevKit V1]([https://www.espressif.com/en/products/devkits/esp32-devkitv1/overview](https://www.amazon.co.uk/dp/B0DJPZHZ1X?ref=ppx_yo2ov_dt_b_fed_asin_title))
  - [MPU-6050 IMU Sensor]([https://invensense.tdk.com/products/motion-tracking/6-axis/mpu-6050/](https://www.amazon.co.uk/Generic-MPU-6050-GY-521-Accelerometer-Gyroscope/dp/B0DLTZJRB3/ref=sr_1_2_sspa?crid=304SD71BFXSMO&dib=eyJ2IjoiMSJ9.Bz_EUOSGrrgaJ-RvW_TVzXq8hmEKcGqdIZO8T79s5CdU-3IpqLB227nOb3hox5LZ7bZVS-oOyeBpaMeTO7NNyoKD1KJdRGRJT3QMvQnrjKk6xjKAndRJBrsOKHS0zjJ2tTq4c-lJsd9HHGchLw8mtI4F9KzPnJwSumPB-ZU2_1pwci5VKwB8QV1TonCRAqotyuJOsYJg4IkQGxc3c1ckKZqFyNv6s1ZJc-oiABJy0H6LofwgNzqGoXk0OEeKndz1HdgLajeha5nU1YwOmz66eyGN6f5I0XZQYh4JGoSmnk8.a1ZwH3W1mnlyd5GERnoh8BIBlUpbCIVjDA7OU7o7_8w&dib_tag=se&keywords=MPU6050&qid=1765391160&sprefix=mpu6050%2Caps%2C101&sr=8-2-spons&aref=f5TQIrwQql&sp_csd=d2lkZ2V0TmFtZT1zcF9hdGY&psc=1))


