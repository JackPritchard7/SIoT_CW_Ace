#include <Arduino.h>
#include <Wire.h>
#include <MicroTFLite.h>
#include <NimBLEDevice.h>
#include "idle_swing_model_data.h"
#include "stroke_type_model_data.h"

// ====================================================
// Configuration
// ====================================================
#define ENABLE_BLE          true
#define SAMPLE_HZ          100.0f // Must match Classifier
#define WINDOW_SIZE        150 // Must match Classifier
#define MOTION_TRIGGER     22.0f // Must match Classifier
#define COOLDOWN_MS        2000
#define POST_COLLECT_MS    700

// ====================================================
// Normalization Parameters 
// ====================================================
static const float FEATURE_MEANS[35] = {
16.304438f, 7.547845f, 32.938269f, 5.361855f, 9.199345f, 19.545837f, -6.323910f, 8.149589f, 16.568597f, -1.961722f, 9.141258f, 12.099851f, 239.858593f, 102.951604f, 427.933503f, -35.282512f, 142.512362f, 233.989117f, 8.358922f, 141.570495f, 225.061068f, -24.221626f, 137.610722f, 229.267547f, 0.383601f, 122.874334f, 127.676642f, 16.876087f, 8.546579f, -1.961722f, 1.073095f, 0.120833f, 0.759431f, 22.141044f, 12.879493f
};

static const float FEATURE_SCALES[35] = {
1.474602f, 0.955251f, 2.013726f, 1.863866f, 1.843300f, 0.668530f, 1.417684f, 1.237854f, 4.477772f, 2.235676f, 1.814325f, 4.243883f, 26.461369f, 17.490440f, 20.446929f, 38.686533f, 22.608125f, 41.450719f, 34.807833f, 22.237971f, 40.293827f, 59.554147f, 26.210300f, 51.694915f, 0.167517f, 24.798179f, 22.769009f, 2.856671f, 1.708978f, 2.235676f, 0.230521f, 0.025959f, 0.134196f, 3.862191f, 2.790438f
};

// ====================================================
// Hardware Configuration
// ====================================================
static const uint8_t MPU_ADDR = 0x68;

// ====================================================
// BLE Configuration
// ====================================================
#define BLE_SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b" // Delete these before uploading to Github
#define BLE_SHOT_CHAR_UUID      "beb5483e-36e1-4688-b7f5-ea07361b26a8" // Delete these before uploading to Github
#define BLE_STATUS_CHAR_UUID    "1c95d5e3-d8f7-413a-bf3d-7a2e5d7be87e" // Delete these before uploading to Github

NimBLEServer* pServer = nullptr;
NimBLECharacteristic* pShotCharacteristic = nullptr;
NimBLECharacteristic* pStatusCharacteristic = nullptr;
bool deviceConnected = false;
bool oldDeviceConnected = false;

class ServerCallbacks: public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* pServer) {
    deviceConnected = true;
    Serial.println("📱 iOS device connected!");
  }
  
  void onDisconnect(NimBLEServer* pServer) {
    deviceConnected = false;
    Serial.println("📱 iOS device disconnected");
  }
};

// ====================================================
// Tensor Arena and Buffers
// ====================================================
constexpr int kTensorArenaSize = 60 * 1024;  // Increased from 40KB to 60KB
alignas(16) static uint8_t tensor_arena[kTensorArenaSize];

struct Sample { 
  float Ax, Ay, Az, Gx, Gy, Gz, Amag, Gmag; 
};

Sample ring[WINDOW_SIZE];
int ringCount = 0;

enum State { IDLE, COLLECTING, COOLDOWN };
State state = IDLE;

unsigned long lastDetectionMs = 0;
unsigned long collectUntilMs = 0;
int totalShots = 0;
float capturedPeakAccel = 0.0f;
float capturedPeakGyro = 0.0f;

// ====================================================
// Feature Extraction
// ====================================================
void computeStats(const float* v, int n, float* out) {
  float sum = 0, sum2 = 0, vmax = v[0];
  
  for (int i = 0; i < n; i++) {
    sum += v[i];
    sum2 += v[i] * v[i];
    if (v[i] > vmax) vmax = v[i];
  }
  
  float mean = sum / n;
  float stdev = sqrtf(max(0.0f, (sum2 / n) - (mean * mean)));
  
  out[0] = mean;
  out[1] = stdev;
  out[2] = vmax;
}

void extractFeatures(float* feats) {
  float channels[8][WINDOW_SIZE];
  
  // Extract channels: Amag, Ax, Ay, Az, Gmag, Gx, Gy, Gz
  for (int i = 0; i < WINDOW_SIZE; i++) {
    channels[0][i] = ring[i].Amag;
    channels[1][i] = ring[i].Ax;
    channels[2][i] = ring[i].Ay;
    channels[3][i] = ring[i].Az;
    channels[4][i] = ring[i].Gmag;
    channels[5][i] = ring[i].Gx;
    channels[6][i] = ring[i].Gy;
    channels[7][i] = ring[i].Gz;
  }
  
  // ===============================================================
  // PART 1: STATISTICAL FEATURES (24) 
  // ===============================================================
  for (int ch = 0; ch < 8; ch++) {
    computeStats(channels[ch], WINDOW_SIZE, &feats[ch * 3]);
  }
  
  int idx = 24;  // Start after statistical features
  
  // ===============================================================
  // PART 2: BIOMECHANICAL FEATURES (6) 
  // ===============================================================
  
  // 1. Wrist pronation/supination ratio
  int pronation_count = 0;
  for (int i = 0; i < WINDOW_SIZE; i++) {
    if (ring[i].Gx > 0) pronation_count++;
  }
  feats[idx++] = (float)pronation_count / WINDOW_SIZE;
  
  // 2. Wrist flexion/extension dominance
  float gy_abs_sum = 0.0f;
  for (int i = 0; i < WINDOW_SIZE; i++) {
    gy_abs_sum += abs(ring[i].Gy);
  }
  feats[idx++] = gy_abs_sum / WINDOW_SIZE;
  
  // 3. Forearm rotation velocity
  float gx_abs_sum = 0.0f;
  for (int i = 0; i < WINDOW_SIZE; i++) {
    gx_abs_sum += abs(ring[i].Gx);
  }
  feats[idx++] = gx_abs_sum / WINDOW_SIZE;
  
  // Find peak accel index (needed for follow-through)
  int peak_accel_idx = 0;
  float peak_accel = ring[0].Amag;
  for (int i = 1; i < WINDOW_SIZE; i++) {
    if (ring[i].Amag > peak_accel) {
      peak_accel = ring[i].Amag;
      peak_accel_idx = i;
    }
  }
  
  // 4. Follow-through intensity
  float follow_through_sum = 0.0f;
  int follow_count = WINDOW_SIZE - peak_accel_idx;
  if (follow_count > 0) {
    for (int i = peak_accel_idx; i < WINDOW_SIZE; i++) {
      follow_through_sum += ring[i].Amag;
    }
    feats[idx++] = follow_through_sum / follow_count;
  } else {
    feats[idx++] = ring[WINDOW_SIZE-1].Amag;
  }
  
  // 5. Lateral swing component
  float ax_abs_sum = 0.0f;
  for (int i = 0; i < WINDOW_SIZE; i++) {
    ax_abs_sum += abs(ring[i].Ax);
  }
  feats[idx++] = ax_abs_sum / WINDOW_SIZE;
  
  // 6. Vertical lift
  float az_sum = 0.0f;
  for (int i = 0; i < WINDOW_SIZE; i++) {
    az_sum += ring[i].Az;
  }
  feats[idx++] = az_sum / WINDOW_SIZE;
  
  // ===============================================================
  // PART 3: TEMPORAL ANALYSIS FEATURES 
  // ===============================================================

  // 7. Swing smoothness (accel jerk)
  float accel_jerk_sum = 0.0f;
  for (int i = 1; i < WINDOW_SIZE; i++) {
    accel_jerk_sum += abs(ring[i].Amag - ring[i-1].Amag);
  }
  feats[idx++] = accel_jerk_sum / (WINDOW_SIZE - 1);
  
  // 8. Trajectory curvature (direction changes)
  float direction_change_sum = 0.0f;
  for (int i = 1; i < WINDOW_SIZE; i++) {
    float v1x = ring[i-1].Ax, v1y = ring[i-1].Ay, v1z = ring[i-1].Az;
    float v2x = ring[i].Ax, v2y = ring[i].Ay, v2z = ring[i].Az;
    float norm1 = sqrtf(v1x*v1x + v1y*v1y + v1z*v1z);
    float norm2 = sqrtf(v2x*v2x + v2y*v2y + v2z*v2z);
    if (norm1 > 0.0f && norm2 > 0.0f) {
      float dot = v1x*v2x + v1y*v2y + v1z*v2z;
      float cos_angle = dot / (norm1 * norm2);
      cos_angle = constrain(cos_angle, -1.0f, 1.0f);
      direction_change_sum += acosf(cos_angle);
    }
  }
  feats[idx++] = direction_change_sum / (WINDOW_SIZE - 1);
  
  // 9. Post-contact follow-through length
  float threshold = peak_accel * 0.3f;
  int sustained_count = 0;
  if (peak_accel_idx < WINDOW_SIZE - 1) {
    for (int i = peak_accel_idx; i < WINDOW_SIZE; i++) {
      if (ring[i].Amag >= threshold) sustained_count++;
    }
    feats[idx++] = (float)sustained_count / (WINDOW_SIZE - peak_accel_idx);
  } else {
    feats[idx++] = 0.0f;
  }
  
  // 10. Energy release rate (middle third)
  int third = WINDOW_SIZE / 3;
  float energy_release = 0.0f;
  for (int i = third; i < 2*third; i++) {
    energy_release += ring[i].Amag;
  }
  feats[idx++] = energy_release / third;
  
  // 11. Recovery phase (last third)
  float recovery = 0.0f;
  for (int i = 2*third; i < WINDOW_SIZE; i++) {
    recovery += ring[i].Amag;
  }
  feats[idx++] = recovery / (WINDOW_SIZE - 2*third);
  
  // Normalize all 35 features
  for (int i = 0; i < 35; i++) {
    feats[i] = (feats[i] - FEATURE_MEANS[i]) / FEATURE_SCALES[i];
  }
}

bool validateFeatures(const float* feats) {
  for (int i = 0; i < 35; i++) {
    if (isnan(feats[i]) || isinf(feats[i])) {
      Serial.printf("❌ Invalid feature[%d]: %.3f\n", i, feats[i]);
      return false;
    }
  }
  return true;
}

// ====================================================
// MPU6050 Functions
// ====================================================
static bool mpuInit() {
  Wire.begin(21, 22); // 21 = SDA = GREEN WIRE|| 22 = SCL = YELLOW WIRE
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x6B);  // PWR_MGMT_1 register
  Wire.write(0x00);  // Wake up MPU6050
  return (Wire.endTransmission(true) == 0);
}

static bool mpuRead(Sample& o) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x3B);  // ACCEL_XOUT_H register
  if (Wire.endTransmission(false) != 0) return false;
  if (Wire.requestFrom((uint8_t)MPU_ADDR, (uint8_t)14, (uint8_t)true) != 14) return false;
  
  // Read accelerometer (3 axes)
  int16_t AcX = (Wire.read() << 8) | Wire.read();
  int16_t AcY = (Wire.read() << 8) | Wire.read();
  int16_t AcZ = (Wire.read() << 8) | Wire.read();
  
  // Skip temperature
  Wire.read();
  Wire.read();
  
  // Read gyroscope (3 axes)
  int16_t GyX = (Wire.read() << 8) | Wire.read();
  int16_t GyY = (Wire.read() << 8) | Wire.read();
  int16_t GyZ = (Wire.read() << 8) | Wire.read();
  
  // Convert to m/s^2 and deg/s
  o.Ax = (AcX / 16384.0f) * 9.81f;
  o.Ay = (AcY / 16384.0f) * 9.81f;
  o.Az = (AcZ / 16384.0f) * 9.81f;
  o.Gx = (GyX / 131.0f);
  o.Gy = (GyY / 131.0f);
  o.Gz = (GyZ / 131.0f);
  
  // Calculate magnitudes
  o.Amag = sqrtf(o.Ax * o.Ax + o.Ay * o.Ay + o.Az * o.Az);
  o.Gmag = sqrtf(o.Gx * o.Gx + o.Gy * o.Gy + o.Gz * o.Gz);
  
  return true;
}

// ====================================================
// ML Inference
// ====================================================
bool runModel(const unsigned char* model_data, const float* feats, float* outputs, int numOutputs) {
  memset(tensor_arena, 0, kTensorArenaSize);
  
  if (!ModelInit(model_data, tensor_arena, kTensorArenaSize)) {
    Serial.println("Model init failed");
    return false;
  }
  
  for (int i = 0; i < 35; i++) {
    ModelSetInput(feats[i], i, false);
  }
  
  if (!ModelRunInference()) {
    Serial.println("Inference failed");
    return false;
  }
  
  for (int i = 0; i < numOutputs; i++) {
    outputs[i] = ModelGetOutput(i);
    if (isnan(outputs[i])) {
      Serial.println("NaN in output");
      return false;
    }
  }
  
  return true;
}

// ====================================================
// Cloud Upload & BLE Transmission
// ====================================================
void sendShotViaBLE(const char* stroke, float swing_mph, float spin_dps, float confidence, int shot_num) {
  if (!ENABLE_BLE) {
    Serial.println("BLE disabled");
    return;
  }
  if (pShotCharacteristic == nullptr) {
    Serial.println("BLE characteristic not initialized");
    return;
  }
  
  // Check actual connection count instead of callback flag
  int connCount = pServer->getConnectedCount();
  if (connCount == 0) {
    Serial.printf("No BLE clients connected (deviceConnected=%d, actual=%d)\n", deviceConnected, connCount);
    return;
  }
  
  // Create JSON payload
  char json[200];
  int len = snprintf(json, sizeof(json), 
    "{\"shot\":%d,\"stroke\":\"%s\",\"swing\":%.1f,\"spin\":%.1f,\"conf\":%.2f,\"ts\":%lu}",
    shot_num, stroke, swing_mph, spin_dps, confidence, millis());
  
  // Send only the actual string length, not the entire buffer
  pShotCharacteristic->setValue((uint8_t*)json, len);
  pShotCharacteristic->notify();
  Serial.printf("📡 Sent via BLE (%d bytes): %s\n", len, json);
}

// ====================================================
// Shot Classification
// ====================================================
void classifyShot() {
  Serial.println("\n========== CLASSIFYING ==========");
  
  // Extract features
  float feats[35];
  extractFeatures(feats);
  
  if (!validateFeatures(feats)) {
    Serial.println("Invalid features\n");
    return;
  }
  
  // Stage A: Idle vs Swing
  float stageA[2];
  if (!runModel(idle_swing_model_data, feats, stageA, 2)) return;
  
  Serial.printf("🔍 Idle:%.2f Swing:%.2f\n", stageA[0], stageA[1]);
  
  if (stageA[1] < 0.5f) {
    Serial.println("Idle motion\n");
    return;
  }
  
  // Stage B: Stroke Type
  float stageB[3];
  if (!runModel(stroke_type_model_data, feats, stageB, 3)) return;
  
  // Find best class
  int best_idx = 0;
  float best_conf = stageB[0];
  for (int i = 1; i < 3; i++) {
    if (stageB[i] > best_conf) {
      best_conf = stageB[i];
      best_idx = i;
    }
  }
  
  const char* labels[] = {"Backhand", "Forehand", "Serve"};
  const char* stroke = labels[best_idx];
  
  // Use captured peak values (not stale buffer data)
  float swing_mph = constrain(capturedPeakAccel * 2.2f, 0.0f, 120.0f);
  float spin_dps = capturedPeakGyro;
  
  Serial.printf("🔍 Peak acceleration: %.2f m/s² → %.1f mph\n", capturedPeakAccel, swing_mph);
  
  // Print result
  totalShots++;
  Serial.printf("\n Shot #%d: %s\n", totalShots, stroke);
  Serial.printf("   Swing: %.1f mph\n", swing_mph);
  Serial.printf("   Spin: %.1f dps\n", spin_dps);
  Serial.printf("   Confidence: %.2f\n\n", best_conf);
  
  // Send via BLE to iOS app (iOS handles cloud upload)
  sendShotViaBLE(stroke, swing_mph, spin_dps, best_conf, totalShots);
}

// ====================================================
// 🏁 SETUP
// ====================================================
void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println("\n============================================");
  Serial.println("🎾 ACE Tennis Classifier V3 (35 Features)");
  Serial.println("   24 Statistical + 6 Biomechanical + 5 Temporal");
  Serial.println("============================================\n");
  
  // Initialize BLE
  if (ENABLE_BLE) {
    Serial.println("Initializing BLE...");
    NimBLEDevice::init("ACE Tennis");
    
    // Create BLE Server
    pServer = NimBLEDevice::createServer();
    pServer->setCallbacks(new ServerCallbacks());
    
    // Create BLE Service
    NimBLEService *pService = pServer->createService(BLE_SERVICE_UUID);
    
    // Shot data characteristic (notify)
    pShotCharacteristic = pService->createCharacteristic(
      BLE_SHOT_CHAR_UUID,
      NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY
    );
    
    // Status characteristic (read)
    pStatusCharacteristic = pService->createCharacteristic(
      BLE_STATUS_CHAR_UUID,
      NIMBLE_PROPERTY::READ
    );
    pStatusCharacteristic->setValue("Ready");
    
    // Start service
    pService->start();
    
    // Start advertising
    NimBLEAdvertising *pAdvertising = NimBLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(BLE_SERVICE_UUID);
    pAdvertising->start();
    
    Serial.println("BLE advertising started!");
    Serial.println("Waiting for iOS app connection...\n");
  }
  
  // Initialize MPU6050
  if (!mpuInit()) {
    Serial.println("MPU6050 failed!");
    while (true) delay(1000);
  }
  Serial.println("MPU6050 ready\n");
  Serial.println("Waiting for motion...\n");
}

// ====================================================
// Main Loop
// ====================================================
void loop() {
  // Handle BLE connection/disconnection
  if (ENABLE_BLE) {
    if (!deviceConnected && oldDeviceConnected) {
      delay(500);
      pServer->startAdvertising();
      Serial.println("📡 Restarting BLE advertising");
      oldDeviceConnected = deviceConnected;
    }
    if (deviceConnected && !oldDeviceConnected) {
      oldDeviceConnected = deviceConnected;
    }
  }
  
  static unsigned long lastSampleMs = 0;
  unsigned long now = millis();
  
  // Sample at 100Hz (every 10ms)
  if (now - lastSampleMs < 10) return;
  lastSampleMs = now;

  // Read sensor data
  Sample s;
  if (!mpuRead(s)) return;

  // Update ring buffer
  if (ringCount < WINDOW_SIZE) {
    ring[ringCount++] = s;
  } else {
    memmove(&ring[0], &ring[1], (WINDOW_SIZE - 1) * sizeof(Sample));
    ring[WINDOW_SIZE - 1] = s;
  }

  // State machine
  switch (state) {
    case IDLE:
      if (s.Amag > MOTION_TRIGGER && (now - lastDetectionMs) > COOLDOWN_MS) {
        Serial.printf("⚡ Motion detected: %.1f m/s²\n", s.Amag);
        capturedPeakAccel = s.Amag;
        capturedPeakGyro = s.Gmag;
        collectUntilMs = now + POST_COLLECT_MS;
        state = COLLECTING;
      }
      break;
      
    case COLLECTING:
      // Track peak values during collection window
      if (s.Amag > capturedPeakAccel) capturedPeakAccel = s.Amag;
      if (s.Gmag > capturedPeakGyro) capturedPeakGyro = s.Gmag;
      
      if (now >= collectUntilMs && ringCount >= WINDOW_SIZE) {
        classifyShot();
        lastDetectionMs = now;
        state = COOLDOWN;
      }
      break;
      
    case COOLDOWN:
      if ((now - lastDetectionMs) >= COOLDOWN_MS) {
        state = IDLE;
      }
      break;
  }
}
