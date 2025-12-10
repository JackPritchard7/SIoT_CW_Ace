#include <WiFi.h>
#include <Wire.h>
#include <InfluxDbClient.h>
#include <InfluxDbCloud.h>

#define DEVICE "ESP32"

// ===== Wi-Fi Credentials =====
#define WIFI_SSID "UPDATE_HERE"
#define WIFI_PASSWORD "UPDATE_HERE"

// ===== InfluxDB Configuration =====
#define INFLUXDB_URL "UPDATE_HERE" 
#define INFLUXDB_TOKEN "UPDATE_HERE"
#define INFLUXDB_ORG "UPDATE_HERE"
#define INFLUXDB_BUCKET "UPDATE_HERE"


// ===== Time Zone =====
#define TZ_INFO "UTC0"

// ===== Sampling Configuration =====

#define SAMPLE_RATE_HZ 100  


// ===== MPU6050 Configuration =====
const int MPU_addr = 0x68; // I2C address of MPU-6050
int16_t AcX, AcY, AcZ, Tmp, GyX, GyY, GyZ;
unsigned long sample_number = 0;
unsigned long batch_count = 0;

// ===== Timing Variables =====
unsigned long last_sample_time = 0;

// ===== InfluxDB Client =====
InfluxDBClient client(INFLUXDB_URL, INFLUXDB_ORG, INFLUXDB_BUCKET, INFLUXDB_TOKEN);
Point sensor("mpu6050_data"); // Measurement name in InfluxDB

// ===== SETUP =====
void setup()
{
  Serial.begin(115200);
  Wire.begin(21, 22); // SDA, SCL

  // Initialize MPU6050
  Wire.beginTransmission(MPU_addr);
  Wire.write(0x6B); // PWR_MGMT_1 register
  Wire.write(0);    // Wake up MPU6050
  Wire.endTransmission(true);

  // Connect to Wi-Fi
  Serial.print("Connecting to WiFi");
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  while (WiFi.status() != WL_CONNECTED)
  {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\n WiFi connected!");

  // Configure InfluxDB write options with batching
  client.setWriteOptions(WriteOptions()
    .writePrecision(WritePrecision::MS)
    .batchSize(BATCH_SIZE)
    .bufferSize(BATCH_SIZE * 2)
    .flushInterval(2)); // Flush after 2s if batch not full
  
  Serial.printf("Batching enabled: upload every %d samples (~%.1f Hz)\n", 
                BATCH_SIZE, 1000.0 / SAMPLE_INTERVAL_MS);

  // Sync time for TLS validation
  timeSync(TZ_INFO, "pool.ntp.org", "time.nis.gov");

  // Validate InfluxDB connection
  if (client.validateConnection())
  {
    Serial.print("Connected to InfluxDB: ");
    Serial.println(client.getServerUrl());
  }
  else
  {
    Serial.print("InfluxDB connection failed: ");
    Serial.println(client.getLastErrorMessage());
  }

  sensor.addTag("device", DEVICE);
}

// ===== LOOP =====
void loop()
{
  unsigned long now = millis();

  // Only sample when enough time has passed
  if (now - last_sample_time >= SAMPLE_INTERVAL_MS)
  {
    last_sample_time = now;

    // === Read MPU6050 data ===
    Wire.beginTransmission(MPU_addr);
    Wire.write(0x3B);
    Wire.endTransmission(false);
    Wire.requestFrom((uint8_t)MPU_addr, (size_t)14, true);


    AcX = Wire.read() << 8 | Wire.read();
    AcY = Wire.read() << 8 | Wire.read();
    AcZ = Wire.read() << 8 | Wire.read();
    Tmp = Wire.read() << 8 | Wire.read();
    GyX = Wire.read() << 8 | Wire.read();
    GyY = Wire.read() << 8 | Wire.read();
    GyZ = Wire.read() << 8 | Wire.read();

    // Convert to physical units
    float Ax = (AcX / 16384.0) * 9.81;
    float Ay = (AcY / 16384.0) * 9.81;
    float Az = (AcZ / 16384.0) * 9.81;
    float Gx = GyX / 131.0;
    float Gy = GyY / 131.0;
    float Gz = GyZ / 131.0;

    // Compute magnitudes
    float A_mag = sqrt(pow(Ax, 2) + pow(Ay, 2) + pow(Az, 2));
    float G_mag = sqrt(pow(Gx, 2) + pow(Gy, 2) + pow(Gz, 2));

    sample_number++;

    // Prepare InfluxDB fields
    sensor.clearFields();
    sensor.addField("Ax", Ax);
    sensor.addField("Ay", Ay);
    sensor.addField("Az", Az);
    sensor.addField("Amag", A_mag);
    sensor.addField("Gx", Gx);
    sensor.addField("Gy", Gy);
    sensor.addField("Gz", Gz);
    sensor.addField("Gmag", G_mag);
    sensor.addField("sample_num", (long)sample_number);

    // Write to InfluxDB (batched)
    if (!client.writePoint(sensor))
    {
      Serial.print("InfluxDB write failed: ");
      Serial.println(client.getLastErrorMessage());
    }

    batch_count++;

    // Print status every batch
    if (batch_count % BATCH_SIZE == 0)
    {
      Serial.printf("Batch uploaded! Sample #%lu | %.1f samples/sec\n",
                    sample_number, 1000.0 / SAMPLE_INTERVAL_MS);
    }
  }
}




