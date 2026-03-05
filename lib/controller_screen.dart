import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import 'package:udp/udp.dart';
import 'package:vibration/vibration.dart';

class RacingPadController {
  RawDatagramSocket? _socket;

  void setupConnection(String pcIp) async {
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    print("UDP Socket bound to port ${_socket!.port}");

    // --- THE LISTENER ---
    _socket!.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        Datagram? dg = _socket!.receive();
        if (dg != null) {
          String message = utf8.decode(dg.data);
          _handleIncomingMessage(message);
        }
      }
    });
  }

  void _handleIncomingMessage(String message) {
    if (message.startsWith("VIB:")) {
      // Split "VIB:255:100" into ["VIB", "255", "100"]
      List<String> parts = message.split(":");
      int largeMotor = int.parse(parts[1]); // Heavy thud (0-255)
      int smallMotor = int.parse(parts[2]); // High-freq buzz (0-255)

      _triggerVibration(largeMotor, smallMotor);
    }
  }

  void _triggerVibration(int large, int small) async {
    if (await Vibration.hasVibrator() ?? false) {
      if (large > 100) {
        // Impact/Collision: Strong pulse
        Vibration.vibrate(duration: 150, amplitude: large); 
      } else if (small > 20) {
        // Road texture/Engine: Subtle, continuous buzz
        Vibration.vibrate(duration: 50, amplitude: small);
      }
    }
  }
}

class RacingControllerScreen extends StatefulWidget {
  final UDP? sender;
  final String? pcIpAddress;
  final int pcPort;

  const RacingControllerScreen({
    super.key,
    required this.sender,
    required this.pcIpAddress,
    required this.pcPort,
  });

  @override
  State<RacingControllerScreen> createState() => _RacingControllerScreenState();
}

class _RacingControllerScreenState extends State<RacingControllerScreen> with TickerProviderStateMixin {
  // ---------------- STATE VARIABLES ----------------
  Offset _shifterOffset = const Offset(15, 0);
  final double _gateLimit = 55.0;
  bool _shiftTriggered = false;
  double _wheelAngle = 0.0;
  final double _maxRotationLimit = 1 * math.pi;
  double _lastTouchAngle = 0.0;
  Offset _navOffset = Offset.zero;
  final double _navRadius = 40;
  bool _hasVibratedAtLimit = false;

  bool _isGasPressed = false;
  bool _isBrakePressed = false;

  late AnimationController _wheelController;
  late Animation<double> _wheelAnimation;
  late AnimationController _shifterController;
  late Animation<Offset> _shifterAnimation;

  UDP? _receiver;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    _wheelController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _wheelController.addListener(() {
      setState(() => _wheelAngle = _wheelAnimation.value);
      _sendSteeringData();
    });
    _shifterController = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    _shifterController.addListener(() => setState(() => _shifterOffset = _shifterAnimation.value));
    _initReceiver();
  }
 
void _initReceiver() async {
    _receiver = await UDP.bind(Endpoint.any(port: Port(5000)));

    _receiver!.asStream().listen((datagram) {
      if (datagram == null) return;

      String message = String.fromCharCodes(datagram.data).trim();
      debugPrint("Received from PC: $message");

      // FIX: Matches "VIB:left,right" from Python
      if (message.startsWith("VIB:")) {
        try {
          String data = message.split(":")[1];
          List<String> parts = data.split(":");
          
          // Parse as double because Python sends 0.0 to 1.0
          double leftIntensity = double.tryParse(parts[0]) ?? 0.0;
          
          if (leftIntensity > 0.7) {
            HapticFeedback.heavyImpact();
          } else if (leftIntensity > 0.3) {
            HapticFeedback.mediumImpact();
          } else if (leftIntensity > 0.05) {
            HapticFeedback.lightImpact();
          }
        } catch (e) {
          debugPrint("Vibration Parse Error: $e");
        }
      } 
      else if (message == "CRASH") {
        HapticFeedback.heavyImpact();
      } 
      else if (message == "ABS") {
        HapticFeedback.mediumImpact();
      }
    });
  }

  // ---------------- LOGIC ----------------
  void _sendData(String message) async {
    if (widget.sender != null && widget.pcIpAddress != null) {
      widget.sender!.send(message.codeUnits, Endpoint.unicast(InternetAddress(widget.pcIpAddress!), port: Port(widget.pcPort)));
    }
  }

  void _sendSteeringData() {
    double normalized = (_wheelAngle / _maxRotationLimit).clamp(-1.0, 1.0);
    _sendData("STEER:${normalized.toStringAsFixed(2)}");
  }

  void _triggerShift(String command) {
    if (_shiftTriggered) return;
    _shiftTriggered = true;
    HapticFeedback.mediumImpact();
    _sendData(command);
    _shifterAnimation = Tween<Offset>(begin: _shifterOffset, end: const Offset(15, 0)).animate(CurvedAnimation(parent: _shifterController, curve: Curves.easeOutCubic));
    _shifterController.forward(from: 0);
    Future.delayed(const Duration(milliseconds: 250), () => _shiftTriggered = false);
  }

  // ---------------- UI BUILDERS ----------------
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. STEERING WHEEL
          Positioned(
            left: w * 0.02,
            top: h * 0.1,
            bottom: h * 0.1,
            child: AspectRatio(
              aspectRatio: 1,
              child: GestureDetector(
                onPanStart: (d) => _lastTouchAngle = math.atan2(d.localPosition.dy - (h*0.4), d.localPosition.dx - (h*0.4)),
                onPanUpdate: (d) {
                  double currentAngle = math.atan2(d.localPosition.dy - (h*0.4), d.localPosition.dx - (h*0.4));
                  double delta = currentAngle - _lastTouchAngle;
                  if (delta > math.pi) delta -= 2 * math.pi;
                  if (delta < -math.pi) delta += 2 * math.pi;
                  double newAngle = (_wheelAngle + delta).clamp(-_maxRotationLimit, _maxRotationLimit);
                  if (newAngle.abs() >= _maxRotationLimit && !_hasVibratedAtLimit) {
                    HapticFeedback.heavyImpact();
                    _hasVibratedAtLimit = true;
                  } else if (newAngle.abs() < _maxRotationLimit) {
                    _hasVibratedAtLimit = false;
                  }
                  setState(() {
                    _wheelAngle = newAngle;
                    _lastTouchAngle = currentAngle;
                  });
                  _sendSteeringData();
                },
                onPanEnd: (_) {
                  _wheelAnimation = Tween<double>(begin: _wheelAngle, end: 0).animate(CurvedAnimation(parent: _wheelController, curve: Curves.easeOutBack));
                  _wheelController.forward(from: 0);
                },
                child: Transform.rotate(angle: _wheelAngle, child: SvgPicture.asset('assets/wheel.svg')),
              ),
            ),
          ),

          // 2. GEAR SHIFTER
          Positioned(
            left: w * 0.42,
            bottom: h * 0.1,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SvgPicture.asset('assets/gate.svg', width: 120),
                GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _shifterOffset = Offset((_shifterOffset.dx + details.delta.dx).clamp(-_gateLimit, _gateLimit), (_shifterOffset.dy + details.delta.dy).clamp(-_gateLimit, _gateLimit));
                      if (_shifterOffset.dy < -50) {
                        _triggerShift("GEAR_UP");
                      } else if (_shifterOffset.dy > 50) _triggerShift("GEAR_DOWN");
                    });
                  },
                  onPanEnd: (_) {
                    _shifterAnimation = Tween<Offset>(begin: _shifterOffset, end: const Offset(15, 0)).animate(CurvedAnimation(parent: _shifterController, curve: Curves.easeOutCubic));
                    _shifterController.forward(from: 0);
                  },
                  child: Transform.translate(offset: _shifterOffset, child: SvgPicture.asset('assets/shifter.svg', width: 60)),
                ),
              ],
            ),
          ),

          // 3. PEDALS - FIXED WITH LISTENER
          Positioned(
            right: w * 0.05,
            bottom: h * 0.05,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildPedal('assets/brake.svg', 'BRAKE', h * 0.35),
                SizedBox(width: w * 0.04),
                _buildPedal('assets/gas.svg', 'GAS', h * 0.45),
              ],
            ),
          ),

          // 4. ACTION BUTTONS - FIXED WITH LISTENER
          Positioned(right: w * 0.18, top: h * 0.15, child: _buildActionButton("assets/Y.svg", "BTN_Y")),
          Positioned(right: w * 0.25, top: h * 0.28, child: _buildActionButton("assets/X.svg", "BTN_X")),
          Positioned(right: w * 0.11, top: h * 0.28, child: _buildActionButton("assets/B.svg", "BTN_B")),
          Positioned(right: w * 0.18, top: h * 0.41, child: _buildActionButton("assets/A.svg", "BTN_A")),

          // 5. NAV JOYSTICK
          Positioned(right: w * 0.28, bottom: h * 0.1, child: _buildNavJoystick()),

          // 6. MENU BUTTONS
          Positioned(
            top: 20,
            left: w * 0.4,
            right: w * 0.4,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildMenuButton("Start", "START"),
                _buildMenuButton("Select", "SELECT"),
              ],
            ),
          ),

          // 7. EXIT
          Positioned(top: 10, right: 10, child: IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 30), onPressed: () => Navigator.pop(context))),
        ],
      ),
    );
  }

  // ---------------- FIXED WIDGET HELPERS ----------------

  Widget _buildPedal(String path, String cmd, double height) {
    bool isPressed = (cmd == 'GAS') ? _isGasPressed : _isBrakePressed;
    return Listener(
      // behavior: HitTestBehavior.opaque ensures the entire area is sensitive to touch
      behavior: HitTestBehavior.opaque, 
      onPointerDown: (_) { 
        setState(() { if (cmd == 'GAS') _isGasPressed = true; else _isBrakePressed = true; }); 
        HapticFeedback.vibrate(); 
        _sendData("${cmd}_ON"); 
      },
      onPointerUp: (_) { 
        setState(() { if (cmd == 'GAS') _isGasPressed = false; else _isBrakePressed = false; }); 
        _sendData("${cmd}_OFF"); 
      },
      // Using onPointerCancel to ensure gas stops if a system dialog or phone call interrupts
      onPointerCancel: (_) { 
        setState(() { if (cmd == 'GAS') _isGasPressed = false; else _isBrakePressed = false; }); 
        _sendData("${cmd}_OFF"); 
      },
      child: AnimatedScale(
        scale: isPressed ? 0.8 : 1.0, 
        duration: const Duration(milliseconds: 100), 
        child: SvgPicture.asset(path, height: height)
      ),
    );
  }

  Widget _buildActionButton(String asset, String cmd) {
  return Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: (_) { 
      HapticFeedback.lightImpact(); 
      _sendData(cmd); // This sends "BTN_A", "BTN_B", etc.
    },
    child: SvgPicture.asset(asset, width: 65),
  );
}

  Widget _buildMenuButton(String label, String cmd) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) { HapticFeedback.mediumImpact(); _sendData(cmd); },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        decoration: BoxDecoration(color: const Color.fromARGB(255, 158, 11, 0).withOpacity(0.8), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white24)),
        child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildNavJoystick() {
    return GestureDetector(
      onPanUpdate: (details) {
        setState(() {
          _navOffset = Offset((_navOffset.dx + details.delta.dx).clamp(-_navRadius, _navRadius), (_navOffset.dy + details.delta.dy).clamp(-_navRadius, _navRadius));
          _sendData("NAV:${(_navOffset.dx/_navRadius).toStringAsFixed(2)},${(-_navOffset.dy/_navRadius).toStringAsFixed(2)}");
        });
      },
      onPanEnd: (_) { setState(() => _navOffset = Offset.zero); _sendData("NAV:0,0"); },
      child: Stack(
        alignment: Alignment.center,
        children: [
          SvgPicture.asset("assets/joysticksurface.svg", width: 100),
          Transform.translate(offset: _navOffset, child: SvgPicture.asset("assets/joystick.svg", width: 50)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _wheelController.dispose();
    _shifterController.dispose();
    _receiver?.close();   // ADD THIS LINE
    super.dispose();
  }
}