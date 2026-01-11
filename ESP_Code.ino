#include <Wire.h>
#include <WiFi.h>
#include <FirebaseESP32.h>
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>

// WiFi Credentials
const char* WIFI_SSID = "ITIDA";
const char* WIFI_PASSWORD = "12345678";

// Firebase Credentials
const char* FIREBASE_HOST = "stem-53cdc-default-rtdb.firebaseio.com";
const char* FIREBASE_AUTH = "UlqdAaYSCRjTcqFBRVW0df1Y513SLgoJ2vuZ2lZO";

// Ultrasonic Sensor Pins
#define TRIG_PIN 5
#define ECHO_PIN 18

// Firebase objects
FirebaseData firebaseData;
FirebaseConfig config;
FirebaseAuth auth;

// MPU6050 object
Adafruit_MPU6050 mpu;

// Timing variables
unsigned long lastSendTime = 0;
const unsigned long sendInterval = 2000; // Send data every 2 seconds

void setup() {
  Serial.begin(115200);
  
  // Initialize ultrasonic sensor pins
  pinMode(TRIG_PIN, OUTPUT);
  pinMode(ECHO_PIN, INPUT);
  
  // Connect to WiFi
  Serial.print("Connecting to WiFi");
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi Connected!");
  Serial.print("IP Address: ");
  Serial.println(WiFi.localIP());
  
  // Initialize MPU6050
  if (!mpu.begin()) {
    Serial.println("Failed to find MPU6050 chip");
    while (1) {
      delay(10);
    }
  }
  Serial.println("MPU6050 Found!");
  
  // Configure MPU6050
  mpu.setAccelerometerRange(MPU6050_RANGE_8_G);
  mpu.setGyroRange(MPU6050_RANGE_500_DEG);
  mpu.setFilterBandwidth(MPU6050_BAND_21_HZ);
  
  // Configure Firebase
  config.host = FIREBASE_HOST;
  config.signer.tokens.legacy_token = FIREBASE_AUTH;
  
  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);
  
  Serial.println("Setup Complete!");
}

void loop() {
  unsigned long currentTime = millis();
  
  // Send data at specified interval
  if (currentTime - lastSendTime >= sendInterval) {
    lastSendTime = currentTime;
    
    // Read MPU6050 data
    sensors_event_t a, g, temp;
    mpu.getEvent(&a, &g, &temp);
    
    // Read Ultrasonic distance
    float distance = getDistance();
    
    // Print to Serial
    Serial.println("\n----- Sensor Readings -----");
    Serial.printf("Acceleration X: %.2f, Y: %.2f, Z: %.2f m/s²\n", a.acceleration.x, a.acceleration.y, a.acceleration.z);
    Serial.printf("Gyroscope X: %.2f, Y: %.2f, Z: %.2f rad/s\n", g.gyro.x, g.gyro.y, g.gyro.z);
    Serial.printf("Temperature: %.2f °C\n", temp.temperature);
    Serial.printf("Distance: %.2f cm\n", distance);
    
    // Send to Firebase
    sendToFirebase(a, g, temp, distance);
  }
}

float getDistance() {
  // Clear the trigger pin
  digitalWrite(TRIG_PIN, LOW);
  delayMicroseconds(2);
  
  // Send 10us pulse
  digitalWrite(TRIG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(TRIG_PIN, LOW);
  
  // Read echo pin
  long duration = pulseIn(ECHO_PIN, HIGH, 30000); // 30ms timeout
  
  // Calculate distance in cm
  float distance = duration * 0.034 / 2;
  
  // Return 0 if timeout or invalid reading
  if (duration == 0 || distance > 400) {
    return 0;
  }
  
  return distance;
}

void sendToFirebase(sensors_event_t &a, sensors_event_t &g, sensors_event_t &temp, float distance) {
  // Create timestamp
  String timestamp = String(millis());
  
  // Send Accelerometer Data
  Firebase.setFloat(firebaseData, "/sensors/accelerometer/x", a.acceleration.x);
  Firebase.setFloat(firebaseData, "/sensors/accelerometer/y", a.acceleration.y);
  Firebase.setFloat(firebaseData, "/sensors/accelerometer/z", a.acceleration.z);
  
  // Send Gyroscope Data
  Firebase.setFloat(firebaseData, "/sensors/gyroscope/x", g.gyro.x);
  Firebase.setFloat(firebaseData, "/sensors/gyroscope/y", g.gyro.y);
  Firebase.setFloat(firebaseData, "/sensors/gyroscope/z", g.gyro.z);
  
  // Send Temperature
  Firebase.setFloat(firebaseData, "/sensors/temperature", temp.temperature);
  
  // Send Ultrasonic Distance
  Firebase.setFloat(firebaseData, "/sensors/distance", distance);
  
  // Send Timestamp
  Firebase.setString(firebaseData, "/sensors/lastUpdate", timestamp);
  
  if (firebaseData.httpCode() == 200) {
    Serial.println("✓ Data sent to Firebase successfully!");
  } else {
    Serial.println("✗ Firebase Error: " + firebaseData.errorReason());
  }
}
