import 'package:flutter/foundation.dart';

/// Shared state between the game world and the Flutter HUD.
class RaceState extends ChangeNotifier {
  double speedKmh = 0;
  int lap = 0;
  double currentLap = 0;
  double? lastLap;
  double? bestLap;
  bool started = false;

  double _sinceNotify = 0;

  void tick(double dt, double speedKmh) {
    this.speedKmh = speedKmh;
    if (started) currentLap += dt;
    _sinceNotify += dt;
    if (_sinceNotify >= 0.1) {
      _sinceNotify = 0;
      notifyListeners();
    }
  }

  void startRace() {
    started = true;
    lap = 1;
    currentLap = 0;
    notifyListeners();
  }

  void completeLap() {
    lastLap = currentLap;
    if (bestLap == null || currentLap < bestLap!) bestLap = currentLap;
    currentLap = 0;
    lap++;
    notifyListeners();
  }
}
