import 'package:flutter/material.dart';
import 'package:church_attendance_app/services/supabase_service.dart';

class LoginViewModel extends ChangeNotifier {
  final SupabaseService _supabaseService = SupabaseService();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String _errorMessage = '';
  String get errorMessage => _errorMessage;

  bool _disposed = false;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<bool> login(String email, String password) async {
    if (email.isEmpty || password.isEmpty) {
      _errorMessage = '이메일과 비밀번호를 입력해주세요.';
      _notify();
      return false;
    }

    _isLoading = true;
    _errorMessage = '';
    _notify();

    try {
      await _supabaseService.init();
      final response = await _supabaseService.signIn(email, password);
      if (response.user != null) {
        _isLoading = false;
        _notify();
        return true;
      } else {
        _errorMessage = '로그인에 실패했습니다.';
        _isLoading = false;
        _notify();
        return false;
      }
    } catch (e) {
      _errorMessage = '로그인 중 오류가 발생했습니다: ${e.toString()}';
      _isLoading = false;
      _notify();
      return false;
    }
  }

  Future<bool> signUp(String email, String password) async {
    if (email.isEmpty || password.isEmpty) {
      _errorMessage = '이메일과 비밀번호를 입력해주세요.';
      _notify();
      return false;
    }

    _isLoading = true;
    _errorMessage = '';
    _notify();

    try {
      await _supabaseService.init();
      final response = await _supabaseService.client.auth.signUp(
        email: email,
        password: password,
      );
      if (response.user != null) {
        _errorMessage = '회원가입이 완료되었습니다. 로그인해주세요.';
        _isLoading = false;
        _notify();
        return true;
      } else {
        _errorMessage = '회원가입에 실패했습니다.';
        _isLoading = false;
        _notify();
        return false;
      }
    } catch (e) {
      _errorMessage = '회원가입 중 오류가 발생했습니다: ${e.toString()}';
      _isLoading = false;
      _notify();
      return false;
    }
  }
}
