import 'package:flutter/foundation.dart';

/// Which bottom navigation tab is active.
class NavProvider extends ChangeNotifier {
  static const home = 0;
  static const cart = 1;
  static const chat = 2;
  static const profile = 3;

  int _tab = home;
  int get tab => _tab;

  void setTab(int index) {
    if (index == _tab) return;
    _tab = index;
    notifyListeners();
  }
}
