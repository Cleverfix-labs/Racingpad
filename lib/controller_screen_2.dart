import 'package:flutter/material.dart';
import 'package:udp/udp.dart';
import 'dart:io';
import 'package:flutter/services.dart';

class ControllerScreen2 extends StatefulWidget {
  final UDP? sender;
  final String? pcIpAddress;
  final int pcPort;

  const ControllerScreen2({
    super.key,
    required this.sender,
    required this.pcIpAddress,
    required this.pcPort,
  });

  @override
  State<ControllerScreen2> createState() => _ControllerScreen2State();
}

class _ControllerScreen2State extends State<ControllerScreen2> {
  Offset leftJoyOffset = Offset.zero;
  Offset rightJoyOffset = Offset.zero;
  final double joyRadius = 40; 

  final Color buttonBlack = const Color(0xFF2C2C2C); 
  final Color backgroundGrey = const Color(0xFF1E1E1E); 
  final Color accentGrey = const Color(0xFF4A4A4A); 

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _send(String message) async {
    if (widget.sender != null && widget.pcIpAddress != null) {
      await widget.sender!.send(
        message.codeUnits,
        Endpoint.unicast(
          InternetAddress(widget.pcIpAddress!),
          port: Port(widget.pcPort),
        ),
      );
    }
  }

  Widget _buildTriggerButton(String label) {
    return GestureDetector(
      onTapDown: (_) {
        HapticFeedback.mediumImpact();
        _send("$label:1.00");
      },
      onTapUp: (_) => _send("$label:0.00"),
      onTapCancel: () => _send("$label:0.00"),
      child: Container(
        width: 80, height: 80,
        decoration: BoxDecoration(
          color: buttonBlack,
          shape: BoxShape.circle,
          border: Border.all(color: accentGrey, width: 3),
        ),
        alignment: Alignment.center,
        child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
      ),
    );
  }

  Widget _buildButton(String label, {double size = 60, String? customMsg}) {
    return GestureDetector(
      onTapDown: (_) {
        HapticFeedback.lightImpact();
        _send(customMsg ?? "BTN_$label");
      },
      child: Container(
        width: size, height: size,
        decoration: BoxDecoration(color: buttonBlack, shape: BoxShape.circle, border: Border.all(color: accentGrey, width: 2)),
        alignment: Alignment.center,
        child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildDPad() {
    return Container(
      width: 140, height: 140,
      decoration: BoxDecoration(color: backgroundGrey, shape: BoxShape.circle, border: Border.all(color: accentGrey)),
      child: Stack(
        children: [
          Align(alignment: Alignment.topCenter, child: IconButton(onPressed: () => _send("BTN_UP"), icon: const Icon(Icons.keyboard_arrow_up, color: Colors.white, size: 35))),
          Align(alignment: Alignment.bottomCenter, child: IconButton(onPressed: () => _send("BTN_DOWN"), icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 35))),
          Align(alignment: Alignment.centerLeft, child: IconButton(onPressed: () => _send("BTN_LEFT"), icon: const Icon(Icons.keyboard_arrow_left, color: Colors.white, size: 35))),
          Align(alignment: Alignment.centerRight, child: IconButton(onPressed: () => _send("BTN_RIGHT"), icon: const Icon(Icons.keyboard_arrow_right, color: Colors.white, size: 35))),
        ],
      ),
    );
  }

  Widget _buildJoystick(bool isLeft) {
    Offset joyOffset = isLeft ? leftJoyOffset : rightJoyOffset;
    return GestureDetector(
      onPanUpdate: (details) {
        setState(() {
          joyOffset += details.delta;
          if (joyOffset.distance > joyRadius) {
            joyOffset = Offset.fromDirection(joyOffset.direction, joyRadius);
          }
          if (isLeft) {
            leftJoyOffset = joyOffset;
          } else {
            rightJoyOffset = joyOffset;
          }
        });
        _send("${isLeft ? 'L' : 'R'}JOY:${(joyOffset.dx/joyRadius).toStringAsFixed(2)},${(joyOffset.dy/joyRadius).toStringAsFixed(2)}");
      },
      onPanEnd: (_) {
        setState(() { if (isLeft) {
          leftJoyOffset = Offset.zero;
        } else {
          rightJoyOffset = Offset.zero;
        } });
        _send(isLeft ? "LJOY:0,0" : "RJOY:0,0");
      },
      child: Container(
        width: 140, height: 140,
        decoration: BoxDecoration(color: backgroundGrey, shape: BoxShape.circle, border: Border.all(color: accentGrey)),
        child: Center(
          child: Transform.translate(
            offset: joyOffset,
            child: Container(width: 60, height: 60, decoration: BoxDecoration(color: accentGrey, shape: BoxShape.circle)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Align(alignment: Alignment.topCenter, child: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white24))),
            Positioned(top: 100, left: 100, child: _buildButton("LB", size: 65)),
            Positioned(top: 100, right: 100, child: _buildButton("RB", size: 65)),
            Positioned(top: 10, left: 10, child: _buildTriggerButton("LT")),
            Positioned(top: 10, right: 10, child: _buildTriggerButton("RT")),
            Positioned(top: 70, left: screenWidth * 0.35, child: _buildButton("▢▢", size: 50, customMsg: "BTN_SEL")),
            Positioned(top: 60, left: screenWidth * 0.46, child: _buildButton("H", size: 60, customMsg: "BTN_HOME")),
            Positioned(top: 70, left: screenWidth * 0.58, child: _buildButton("≡", size: 50, customMsg: "BTN_STA")),
            Positioned(bottom: 20, left: screenWidth * 0.25, child: _buildJoystick(true)),
            Positioned(bottom: 20, right: screenWidth * 0.25, child: _buildJoystick(false)),
            Positioned(bottom: 40, left: 20, child: _buildDPad()), // 🔥 RESTORED D-PAD
            Positioned(bottom: 20, right: 70, child: _buildButton("A")),
            Positioned(bottom: 80, right: 10, child: _buildButton("B")),
            Positioned(bottom: 80, right: 130, child: _buildButton("X")),
            Positioned(bottom: 140, right: 70, child: _buildButton("Y")),
          ],
        ),
      ),
    );
  }
}