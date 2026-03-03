import 'controller_screen.dart';
import 'controller_screen_2.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:udp/udp.dart';
import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:racingpad_app/update_service.dart';

void main() async {
  // 1. Ensure the Flutter framework is ready for plugin calls
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Initialize AdMob
  await MobileAds.instance.initialize();

  // 3. Start the Update Check (non-blocking)
  // We don't 'await' this so the app doesn't stay on a black screen if the internet is slow.
  UpdateService.checkAndApplyUpdate();

  // 4. Launch your app UI
  runApp(const RacingPadApp());
}

class RacingPadApp extends StatelessWidget {
  const RacingPadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark, // Premium dark feel for gamers
        
        // 60% Dominant: Midnight Blue
        primaryColor: const Color(0xFF03045E), 
        scaffoldBackgroundColor: const Color(0xFF03045E),

        // Updated Color Scheme
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF03045E),
          brightness: Brightness.dark,
          secondary: const Color(0xFFFF1801), // Racing Red
          surface: const Color(0xFF0077B6),    // Electric Blue
        ),

        // Polished AppBar
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF03045E),
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 0,
        ),

        // Navigation Bar Styling
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF02022E),
          selectedItemColor: Color(0xFF0077B6),
          unselectedItemColor: Colors.grey,
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  bool isConnected = false;
  String? pcIpAddress;
  int pcPort = 5000;
  UDP? sender;

  // ================= TIMER & AD LOGIC =================
  int _remainingSeconds = 1800; 
  Timer? _sessionTimer;
  
  RewardedAd? _rewardedAd;
  bool _isAdLoading = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _loadSavedTime();
    _loadRewardedAd();
  }

  Future<void> _loadSavedTime() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _remainingSeconds = prefs.getInt('remaining_seconds') ?? 1800;
    });
  }

  Future<void> _saveTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('remaining_seconds', _remainingSeconds);
  }

  void _loadRewardedAd() {
    setState(() => _isAdLoading = true);
    RewardedAd.load(
      adUnitId: 'ca-app-pub-6673674931028953/4012117648', 
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          setState(() {
            _rewardedAd = ad;
            _isAdLoading = false;
          });
        },
        onAdFailedToLoad: (LoadAdError error) {
          setState(() => _isAdLoading = false);
          _rewardedAd = null;
        },
      ),
    );
  }

  void _startSessionTimer() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
        if (_remainingSeconds % 30 == 0) _saveTime(); 
      } else {
        _stopSessionTimer();
        _handleTimeOut();
      }
    });
  }

  void _stopSessionTimer() {
    _sessionTimer?.cancel();
    _saveTime();
  }

  void _handleTimeOut() {
    if (Navigator.canPop(context)) {
      Navigator.popUntil(context, (route) => route.isFirst);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF02022E),
        title: const Icon(Icons.check_circle, color: Colors.green, size: 60),
        content: const Text(
          "Reward Collected!\n30 Minutes added to your account.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("AWESOME", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0077B6))),
          ),
        ],
      ),
    );
  }

  void _watchAdToCollectTime() {
    if (_rewardedAd == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Ad is still buffering, try again in a moment!"),
          backgroundColor: Color(0xFF0077B6),
        ),
      );
      _loadRewardedAd(); 
      return;
    }

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadRewardedAd();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _loadRewardedAd();
      },
    );

    _rewardedAd!.show(onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
      setState(() {
        _remainingSeconds += 1800; 
      });
      _saveTime();
      _showSuccessDialog();
    });
  }

  String _getFormattedTime() {
    int hrs = _remainingSeconds ~/ 3600;
    int mins = (_remainingSeconds % 3600) ~/ 60;
    int secs = _remainingSeconds % 60;
    if (hrs > 0) return "${hrs.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}";
    return "${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}";
  }

  void _navigateToController(Widget screen) async {
    if (_remainingSeconds <= 0) return;
    
    if (sender == null || pcIpAddress == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Not connected to PC"), backgroundColor: Colors.red),
      );
      return;
    }

    _startSessionTimer();
    
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => screen),
      );
    } catch (e) {
      debugPrint("Navigation Error: $e");
    } finally {
      _stopSessionTimer();
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
  }

  // ================= NAVIGATION & CONNECTION =================

  void _onItemTapped(int index) => setState(() => _selectedIndex = index);

  void _openScanner() {
    bool isScanning = false;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text("Scan PC QR Code")),
          body: MobileScanner(
            onDetect: (capture) async {
              if (isScanning) return;
              isScanning = true;
              final List<Barcode> barcodes = capture.barcodes;
              if (barcodes.isEmpty) return;
              final String code = barcodes.first.rawValue ?? "";
              List<String> parts = code.split(':');
              if (parts.length == 2) {
                final udpInstance = await UDP.bind(Endpoint.any());
                if (!mounted) return;
                setState(() {
                  sender = udpInstance;
                  pcIpAddress = parts[0];
                  pcPort = int.parse(parts[1]);
                  isConnected = true;
                });
                await Future.delayed(const Duration(milliseconds: 300));
                if (mounted) Navigator.of(context).pop();
              }
            },
          ),
        ),
      ),
    );
  }

  void _sendPing() async {
    if (sender != null && pcIpAddress != null) {
      await sender!.send("ping".codeUnits, Endpoint.unicast(InternetAddress(pcIpAddress!), port: Port(pcPort)));
    }
  }

  void _disconnect() {
    setState(() {
      sender?.close();
      sender = null;
      pcIpAddress = null;
      isConnected = false;
    });
  }

  // ================= UI TABS =================

  Widget _buildHome() {
    bool outOfTime = _remainingSeconds <= 0;
    return Center( 
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text("Controller Layout", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 40),
          if (outOfTime)
            const Text("Out of time! Go to 'More Time' tab.", style: TextStyle(color: Color(0xFFFF1801), fontWeight: FontWeight.bold))
          else ...[
            SizedBox(
              width: 220, height: 55,
              child: ElevatedButton.icon(
                onPressed: isConnected ? () => _navigateToController(RacingControllerScreen(sender: sender, pcIpAddress: pcIpAddress, pcPort: pcPort)) : null,
                icon: const Icon(Icons.directions_car),
                label: const Text("Steering Mode"),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0077B6), foregroundColor: Colors.white),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 220, height: 55,
              child: ElevatedButton.icon(
                onPressed: isConnected ? () => _navigateToController(ControllerScreen2(sender: sender, pcIpAddress: pcIpAddress, pcPort: pcPort)) : null,
                icon: const Icon(Icons.gamepad),
                label: const Text("Normal Mode"),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0077B6), foregroundColor: Colors.white),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConnect() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(isConnected ? Icons.check_circle : Icons.error_outline, size: 80, color: isConnected ? Colors.green : const Color(0xFFFF1801)),
          const SizedBox(height: 20),
          Text(isConnected ? "Connected to PC" : "Not Connected", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
          if (isConnected) ...[
            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _sendPing, 
                  icon: const Icon(Icons.sensors), 
                  label: const Text("Ping"),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0077B6), foregroundColor: Colors.white),
                ),
                const SizedBox(width: 15),
                ElevatedButton.icon(
                  onPressed: _disconnect, 
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red[900], foregroundColor: Colors.white), 
                  icon: const Icon(Icons.link_off), 
                  label: const Text("Disconnect")
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: _openScanner, 
              icon: const Icon(Icons.qr_code_scanner), 
              label: const Text("Scan PC QR Code"),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0077B6), foregroundColor: Colors.white),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMoreTime() {
    return Column(
      children: [
        Expanded(
          flex: 1,
          child: Container(
            width: double.infinity,
            color: const Color(0xFF02022E),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("COLLECTED TIME", style: TextStyle(fontSize: 16, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
                Text(_getFormattedTime(), style: const TextStyle(fontSize: 54, fontWeight: FontWeight.bold, color: Colors.white)),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 1,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("Need more gameplay time?", style: TextStyle(fontSize: 16, color: Colors.white)),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _isAdLoading ? null : _watchAdToCollectTime,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF1801), // 10% Accent: Racing Red
                    foregroundColor: Colors.white, 
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15)
                  ),
                  icon: _isAdLoading 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.play_circle_fill),
                  label: Text(_isAdLoading ? "LOADING AD..." : "FREE TIME (Watch Ad)", style: const TextStyle(fontSize: 18)),
                ),
                const SizedBox(height: 10),
                const Text("+30 Minutes per Ad", style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> pages = [_buildHome(), _buildConnect(), _buildMoreTime()];

    return Scaffold(
      appBar: AppBar(
  title: const Text(
    "RACINGPAD", 
    style: TextStyle(
      fontFamily: 'BebasNeue',
      fontSize: 28,          // Bebas looks best when large
      letterSpacing: 1.5,     // Adds a premium "spaced" look
      fontWeight: FontWeight.bold,
    ),
  ),
  centerTitle: true,
),
      body: Stack(
        children: [
          pages[_selectedIndex],
          if (_selectedIndex != 2)
            Positioned(
              top: 10, left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: const Color(0xFFFF1801).withOpacity(0.8), borderRadius: BorderRadius.circular(20)),
                child: Text(_getFormattedTime(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.qr_code), label: "Connect"),
          BottomNavigationBarItem(icon: Icon(Icons.history_toggle_off), label: "More Time"),
        ],
      ),
    );
  }
}