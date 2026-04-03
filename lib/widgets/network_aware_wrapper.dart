import 'dart:async';
import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../services/network_service.dart';

class NetworkAwareWrapper extends StatefulWidget {
  final Widget child;
  final NetworkService networkService;

  const NetworkAwareWrapper({
    super.key,
    required this.child,
    required this.networkService,
  });

  @override
  State<NetworkAwareWrapper> createState() => _NetworkAwareWrapperState();
}

class _NetworkAwareWrapperState extends State<NetworkAwareWrapper>
    with SingleTickerProviderStateMixin {
  bool _isConnected = true;
  late StreamSubscription<bool> _subscription;
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));

    // Check initial connectivity
    widget.networkService.isConnected.then((connected) {
      if (mounted) {
        setState(() => _isConnected = connected);
        if (!connected) _animationController.forward();
      }
    });

    // Listen to connectivity changes
    _subscription =
        widget.networkService.onConnectivityChanged.listen((connected) {
      if (mounted) {
        setState(() => _isConnected = connected);
        if (!connected) {
          _animationController.forward();
        } else {
          _animationController.reverse();
        }
      }
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (!_isConnected)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SlideTransition(
              position: _slideAnimation,
              child: Material(
                color: Colors.transparent,
                child: SafeArea(
                  bottom: false,
                  child: Container(
                    width: double.infinity,
                    color: AppColors.error,
                    padding: const EdgeInsets.symmetric(
                        vertical: 8, horizontal: 16),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.wifi_off,
                            color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'No Internet Connection',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
