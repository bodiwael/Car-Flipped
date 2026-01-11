import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:math' as math;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const CarMonitorApp());
}

class CarMonitorApp extends StatelessWidget {
  const CarMonitorApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Car Flip Monitor',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.grey[50],
        cardTheme: CardThemeData(
          elevation: 3,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      home: const CarDashboard(),
    );
  }
}

class CarDashboard extends StatefulWidget {
  const CarDashboard({Key? key}) : super(key: key);

  @override
  State<CarDashboard> createState() => _CarDashboardState();
}

class _CarDashboardState extends State<CarDashboard> {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  Map<String, CarData> carsData = {};

  @override
  void initState() {
    super.initState();
    _setupListeners();
  }

  void _setupListeners() {
    // Listen to Car3 - Fixed orientation (not flipped)
    _database.child('Car3').onValue.listen((event) {
      if (event.snapshot.value != null) {
        setState(() {
          carsData['Car3'] = CarData.fromMap(
            Map<String, dynamic>.from(event.snapshot.value as Map),
            isFixedOrientation: true, // Car 3 is always upright
          );
        });
      }
    });

    // Listen to Car4 - Normal flip detection
    _database.child('Car4').onValue.listen((event) {
      if (event.snapshot.value != null) {
        setState(() {
          carsData['Car4'] = CarData.fromMap(
            Map<String, dynamic>.from(event.snapshot.value as Map),
            isFixedOrientation: false,
          );
        });
      }
    });
  }

  Future<void> _makeEmergencyCall() async {
    final Uri phoneUri = Uri(scheme: 'tel', path: '122');

    try {
      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not open phone dialer'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Car Flip Monitor', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.blue[700],
        actions: [
          // Emergency call button
          // Padding(
          //   padding: const EdgeInsets.only(right: 8),
          //   child: ElevatedButton.icon(
          //     onPressed: _makeEmergencyCall,
          //     icon: const Icon(Icons.phone, size: 20),
          //     label: const Text('122'),
          //     style: ElevatedButton.styleFrom(
          //       backgroundColor: Colors.red,
          //       foregroundColor: Colors.white,
          //       shape: RoundedRectangleBorder(
          //         borderRadius: BorderRadius.circular(20),
          //       ),
          //     ),
          //   ),
          // ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() {});
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (carsData.containsKey('Car3'))
              CarCard(
                title: 'Car 3',
                data: carsData['Car3']!,
                icon: Icons.directions_car,
                color: Colors.blue,
                onEmergencyCall: _makeEmergencyCall,
              ),
            const SizedBox(height: 16),
            if (carsData.containsKey('Car4'))
              CarCard(
                title: 'Car 4',
                data: carsData['Car4']!,
                icon: Icons.directions_car,
                color: Colors.green,
                onEmergencyCall: _makeEmergencyCall,
              ),
            if (carsData.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: const [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Waiting for car data...'),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _makeEmergencyCall,
        backgroundColor: Colors.red,
        icon: const Icon(Icons.emergency),
        label: const Text('Emergency Call 122'),
      ),
    );
  }
}

class CarData {
  final double distance;
  final bool flipped;
  final double pitch;
  final double roll;
  final String timestamp;
  final double latitude;
  final double longitude;
  final bool isFixedOrientation;

  CarData({
    required this.distance,
    required this.flipped,
    required this.pitch,
    required this.roll,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.isFixedOrientation,
  });

  factory CarData.fromMap(Map<String, dynamic> map, {required bool isFixedOrientation}) {
    return CarData(
      distance: (map['distance'] ?? 0).toDouble(),
      // If fixed orientation, always false. Otherwise read from Firebase
      flipped: isFixedOrientation ? false : (map['flipped'] ?? false),
      pitch: (map['pitch'] ?? 0).toDouble(),
      roll: (map['roll'] ?? 0).toDouble(),
      timestamp: map['timestamp']?.toString() ?? '0',
      latitude: (map['latitude'] ?? 0).toDouble(),
      longitude: (map['longitude'] ?? 0).toDouble(),
      isFixedOrientation: isFixedOrientation,
    );
  }

  // Calculate flip risk based on roll angle (0-100%)
  double get flipRisk {
    // If fixed orientation, always return 0 risk
    if (isFixedOrientation) return 0;

    double absRoll = roll.abs();
    if (absRoll < 30) return 0;
    if (absRoll >= 90) return 100;
    return ((absRoll - 30) / 60) * 100;
  }

  Color get riskColor {
    if (flipped) return Colors.red;
    if (flipRisk > 70) return Colors.orange;
    if (flipRisk > 40) return Colors.amber;
    return Colors.green;
  }

  String get riskLevel {
    if (isFixedOrientation) return 'STABLE';
    if (flipped) return 'FLIPPED!';
    if (flipRisk > 70) return 'CRITICAL';
    if (flipRisk > 40) return 'WARNING';
    return 'SAFE';
  }

  String get locationString {
    if (latitude == 0 && longitude == 0) return 'No location';
    return '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
  }

  Future<String> getAddressFromCoordinates() async {
    if (latitude == 0 && longitude == 0) return 'No location';

    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(latitude, longitude);

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];

        // Build address string with available components
        List<String> addressParts = [];

        if (place.street != null && place.street!.isNotEmpty) {
          addressParts.add(place.street!);
        }
        if (place.subLocality != null && place.subLocality!.isNotEmpty) {
          addressParts.add(place.subLocality!);
        }
        if (place.locality != null && place.locality!.isNotEmpty) {
          addressParts.add(place.locality!);
        }
        if (place.administrativeArea != null && place.administrativeArea!.isNotEmpty) {
          addressParts.add(place.administrativeArea!);
        }
        if (place.country != null && place.country!.isNotEmpty) {
          addressParts.add(place.country!);
        }

        return addressParts.isNotEmpty ? addressParts.join(', ') : locationString;
      }

      return locationString;
    } catch (e) {
      print('Error getting address: $e');
      return locationString;
    }
  }
}

class CarCard extends StatelessWidget {
  final String title;
  final CarData data;
  final IconData icon;
  final Color color;
  final VoidCallback onEmergencyCall;

  const CarCard({
    Key? key,
    required this.title,
    required this.data,
    required this.icon,
    required this.color,
    required this.onEmergencyCall,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      color: data.flipped ? Colors.red[50] : Colors.white,
      child: ExpansionTile(
        leading: Icon(
          icon,
          size: 40,
          color: data.flipped ? Colors.red : color,
        ),
        title: Row(
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: data.flipped ? Colors.red[900] : Colors.black87,
              ),
            ),
            // if (data.isFixedOrientation) ...[
            //   const SizedBox(width: 8),
            //   Container(
            //     padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            //     decoration: BoxDecoration(
            //       color: Colors.blue[100],
            //       borderRadius: BorderRadius.circular(12),
            //       border: Border.all(color: Colors.blue),
            //     ),
            //     child: const Text(
            //       'FIXED',
            //       style: TextStyle(
            //         fontSize: 10,
            //         fontWeight: FontWeight.bold,
            //         color: Colors.blue,
            //       ),
            //     ),
            //   ),
            // ],
          ],
        ),
        subtitle: Row(
          children: [
            Icon(
              data.flipped ? Icons.warning : Icons.check_circle,
              size: 16,
              color: data.riskColor,
            ),
            const SizedBox(width: 4),
            Text(
              data.riskLevel,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: data.riskColor,
              ),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Flip Risk Indicator with Slider (only if not fixed orientation)
                if (!data.isFixedOrientation)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: data.riskColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: data.riskColor.withOpacity(0.3)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Flip Risk',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[800],
                              ),
                            ),
                            Text(
                              '${data.flipRisk.toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: data.riskColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 8,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
                            activeTrackColor: data.riskColor,
                            inactiveTrackColor: Colors.grey[300],
                            thumbColor: data.riskColor,
                          ),
                          child: Slider(
                            value: data.flipRisk.clamp(0, 100),
                            min: 0,
                            max: 100,
                            onChanged: null,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Safe', style: TextStyle(color: Colors.grey[600])),
                            Text('Critical', style: TextStyle(color: Colors.grey[600])),
                          ],
                        ),
                      ],
                    ),
                  ),
                if (!data.isFixedOrientation) const SizedBox(height: 20),

                // Stable orientation indicator for Car 3
                if (data.isFixedOrientation)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green, width: 2),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green[700], size: 32),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Orientation Stable',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[900],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (data.isFixedOrientation) const SizedBox(height: 20),

                // Flipped Status (if flipped)
                if (data.flipped && !data.isFixedOrientation)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red, width: 2),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning, color: Colors.red[900], size: 32),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'CAR HAS FLIPPED!',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.red[900],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (data.flipped && !data.isFixedOrientation) const SizedBox(height: 16),

                // Location with address
                _buildLocationRow(
                  data,
                ),
                const Divider(height: 24),

                // Distance (in cm)
                _buildMetricRow(
                  'Distance',
                  '${data.distance.toStringAsFixed(2)} cm',
                  Icons.straighten,
                  Colors.blue,
                ),
                const Divider(height: 24),

                // Pitch with visual indicator
                _buildAngleRow(
                  'Pitch',
                  data.pitch,
                  Icons.rotate_90_degrees_ccw,
                  Colors.purple,
                ),
                const Divider(height: 24),

                // Roll with visual indicator
                _buildAngleRow(
                  'Roll',
                  data.roll,
                  Icons.rotate_left,
                  data.flipped ? Colors.red : Colors.orange,
                ),
                const Divider(height: 24),

                // Timestamp
                _buildMetricRow(
                  'Timestamp',
                  data.timestamp,
                  Icons.access_time,
                  Colors.grey[700]!,
                ),
                const SizedBox(height: 20),

                // Emergency button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onEmergencyCall,
                    icon: const Icon(Icons.phone),
                    label: const Text('Emergency Call 122'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationRow(CarData data) {
    return FutureBuilder<String>(
      future: data.getAddressFromCoordinates(),
      builder: (context, snapshot) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.location_on, color: Colors.red, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Location',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Address line
              if (snapshot.connectionState == ConnectionState.waiting)
                Row(
                  children: const [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('Getting address...', style: TextStyle(fontSize: 14)),
                  ],
                )
              else if (snapshot.hasData)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.place, color: Colors.red, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        snapshot.data!,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                )
              else
                Text(
                  data.locationString,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                ),
              const SizedBox(height: 8),
              // Coordinates line
              Row(
                children: [
                  const Icon(Icons.my_location, color: Colors.grey, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    data.locationString,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMetricRow(String label, String value, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAngleRow(String label, double angle, IconData icon, Color color) {
    return Column(
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Transform.rotate(
                angle: angle * math.pi / 180,
                child: Icon(icon, color: color, size: 24),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
            ),
            Text(
              '${angle.toStringAsFixed(2)}°',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Visual angle indicator
        Container(
          height: 6,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            color: Colors.grey[300],
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: ((angle.abs() / 90).clamp(0, 1)),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: color,
              ),
            ),
          ),
        ),
      ],
    );
  }
}