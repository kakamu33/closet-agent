import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../settings/domain/user_profile.dart';
import '../domain/auth_repository.dart';

enum _AuthMode { login, register, reset }

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  final _username = TextEditingController();
  final _nickname = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _verificationCode = TextEditingController();
  final _identifierFocus = FocusNode();
  final _passwordFocus = FocusNode();
  var _identifierValidated = false;
  var _passwordValidated = false;
  var _mode = _AuthMode.login;
  var _submitting = false;
  var _obscurePassword = true;
  String? _submitError;
  String? _registrationVerificationId;
  late final AnimationController _validationShakeController;
  static final _usernamePattern = RegExp(r'^[A-Za-z][A-Za-z0-9_]{4,19}$');

  @override
  void dispose() {
    _identifier.dispose();
    _username.dispose();
    _nickname.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _verificationCode.dispose();
    _identifierFocus.dispose();
    _passwordFocus.dispose();
    _validationShakeController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _validationShakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _restoreLastLoginIdentifier();
    _identifierFocus.addListener(() {
      if (!_identifierFocus.hasFocus && _identifier.text.trim().isNotEmpty) {
        setState(() => _identifierValidated = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _formKey.currentState?.validate();
        });
      }
    });
    _passwordFocus.addListener(() {
      if (!_passwordFocus.hasFocus && _password.text.isNotEmpty) {
        setState(() => _passwordValidated = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _formKey.currentState?.validate();
        });
      }
    });
  }

  Future<void> _restoreLastLoginIdentifier() async {
    final identifier = await ref.read(authRepositoryProvider).lastLoginIdentifier();
    if (mounted && identifier != null) _identifier.text = identifier;
  }

  void _shakeValidationErrors() {
    _validationShakeController.forward(from: 0);
  }

  Widget _buildShakingErrorText(BuildContext context, String errorText) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _validationShakeController,
      builder: (context, child) {
        final progress = _validationShakeController.value;
        final direction = progress < .25
            ? -1.0
            : progress < .5
            ? 1.0
            : progress < .75
            ? -1.0
            : 1.0;
        return Transform.translate(
          offset: Offset(7 * (1 - progress) * direction, 0),
          child: child,
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(left: 12, top: 4),
        child: Text(
          errorText,
          style: TextStyle(color: colors.error, fontSize: 12),
        ),
      ),
    );
  }

  void _switchMode(_AuthMode mode) {
    _formKey.currentState?.reset();
    setState(() {
      _mode = mode;
      _submitError = null;
      _registrationVerificationId = null;
      _verificationCode.clear();
    });
  }

  Future<void> _submit() async {
    if (_mode == _AuthMode.login) {
      setState(() {
        _identifierValidated = true;
        _passwordValidated = true;
      });
    }
    if (!_formKey.currentState!.validate()) {
      if (_mode == _AuthMode.login) _shakeValidationErrors();
      return;
    }
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final auth = ref.read(authSessionProvider.notifier);
      if (_mode == _AuthMode.login) {
        await auth.login(
          identifier: _identifier.text,
          password: _password.text,
        );
      } else if (_mode == _AuthMode.register) {
        final verificationId = _registrationVerificationId;
        if (verificationId == null) {
          final id = await ref
              .read(authRepositoryProvider)
              .sendRegistrationVerificationCode(email: _email.text);
          if (mounted) {
            setState(() => _registrationVerificationId = id);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('验证码已发送到邮箱，请在 10 分钟内完成验证。')),
            );
          }
          return;
        }
        final user = await auth.register(
          username: _username.text,
          nickname: _nickname.text,
          email: _email.text,
          password: _password.text,
          verificationId: verificationId,
          verificationCode: _verificationCode.text,
        );
        await ref
            .read(userProfileProvider.notifier)
            .save(
              UserProfile(
                id: user.id,
                nickname: user.nickname,
                signature: UserProfile.defaults.signature,
              ),
            );
      } else {
        await ref
            .read(authRepositoryProvider)
            .requestPasswordReset(email: _email.text);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('本地测试版已保留找回流程，接入云端后将发送邮箱验证码。')),
          );
        }
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _submitError = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _submitError = '登录暂时失败，请稍后重试');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String get _title => switch (_mode) {
    _AuthMode.login => '欢迎回来',
    _AuthMode.register => '创建你的叠序账号',
    _AuthMode.reset => '找回密码',
  };

  String get _subtitle => switch (_mode) {
    _AuthMode.login => '用用户名或邮箱继续整理你的衣橱。',
    _AuthMode.register => '用户名是唯一凭证，邮箱用于验证与找回密码。',
    _AuthMode.reset => '云端接入后，我们会向绑定邮箱发送验证码。',
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.disabled,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: colors.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.checkroom_rounded,
                          color: colors.primary,
                          size: 36,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      _title,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _subtitle,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 30),
                    if (_mode == _AuthMode.login) ...[
                      Column(
                        children: [
                      TextFormField(
                        controller: _identifier,
                        focusNode: _identifierFocus,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) {
                          if (_identifierValidated) {
                            _formKey.currentState?.validate();
                          }
                        },
                        decoration: const InputDecoration(
                          hintText: '用户名或邮箱',
                          floatingLabelBehavior: FloatingLabelBehavior.never,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          prefixIcon: Icon(Icons.person_outline),
                          errorMaxLines: 3,
                        ),
                        validator: (value) => _identifierValidated
                            ? _validateLoginIdentifier(value)
                            : null,
                        errorBuilder: _buildShakingErrorText,
                      ),
                      const SizedBox(height: 26),
                      _passwordField(colors),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _submitting
                              ? null
                              : () => _switchMode(_AuthMode.reset),
                          child: const Text('忘记密码？'),
                        ),
                      ),
                        ],
                      ),
                    ],
                    if (_mode == _AuthMode.register) ...[
                      TextFormField(
                        controller: _username,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          hintText: '用户名',
                          prefixIcon: Icon(Icons.alternate_email),
                          floatingLabelBehavior: FloatingLabelBehavior.never,
                          errorMaxLines: 3,
                          helperText: '5-20 位，首位英文，仅含英文、数字、下划线',
                        ),
                        validator: (value) =>
                            RegExp(
                              r'^[A-Za-z][A-Za-z0-9_]{4,19}$',
                            ).hasMatch(value?.trim() ?? '')
                            ? null
                            : '用户名格式不正确',
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _nickname,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          hintText: '昵称',
                          prefixIcon: Icon(Icons.badge_outlined),
                          floatingLabelBehavior: FloatingLabelBehavior.never,
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? '请输入昵称'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          hintText: '邮箱',
                          prefixIcon: Icon(Icons.mail_outline),
                          floatingLabelBehavior: FloatingLabelBehavior.never,
                        ),
                        validator: (value) =>
                            (value?.contains('@') ?? false) ? null : '请输入有效邮箱',
                      ),
                      const SizedBox(height: 14),
                      _passwordField(colors),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _confirmPassword,
                        obscureText: true,
                        decoration: const InputDecoration(
                          hintText: '确认密码',
                          prefixIcon: Icon(Icons.lock_outline),
                          floatingLabelBehavior: FloatingLabelBehavior.never,
                        ),
                        validator: (value) =>
                            value == _password.text ? null : '两次输入的密码不一致',
                      ),
                      if (_registrationVerificationId != null) ...[
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _verificationCode,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          decoration: const InputDecoration(
                            hintText: '邮箱验证码',
                            prefixIcon: Icon(Icons.verified_user_outlined),
                            floatingLabelBehavior: FloatingLabelBehavior.never,
                          ),
                          validator: (value) =>
                              RegExp(r'^\d{6}$').hasMatch(value?.trim() ?? '')
                              ? null
                              : '请输入邮箱收到的 6 位验证码',
                        ),
                      ],
                    ],
                    if (_mode == _AuthMode.reset) ...[
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: '绑定邮箱',
                          prefixIcon: Icon(Icons.mail_outline),
                        ),
                        validator: (value) =>
                            (value?.contains('@') ?? false) ? null : '请输入有效邮箱',
                      ),
                    ],
                    const SizedBox(height: 28),
                    if (_submitError != null) ...[
                      const SizedBox(height: 18),
                      Semantics(
                        liveRegion: true,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            color: colors.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline, color: colors.error),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _submitError!,
                                  style: TextStyle(color: colors.onErrorContainer),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          _submitting
                              ? '处理中…'
                              : switch (_mode) {
                                  _AuthMode.login => '登录',
                                  _AuthMode.register => _registrationVerificationId == null
                                      ? '发送邮箱验证码'
                                      : '验证并创建账号',
                                  _AuthMode.reset => '发送找回说明',
                                },
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_mode != _AuthMode.login)
                      TextButton(
                        onPressed: _submitting
                            ? null
                            : () => _switchMode(_AuthMode.login),
                        child: const Text('已有账号？去登录'),
                      ),
                    if (_mode == _AuthMode.login)
                      TextButton(
                        onPressed: _submitting
                            ? null
                            : () => _switchMode(_AuthMode.register),
                        child: const Text('还没有账号？创建账号'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _validateLoginIdentifier(String? value) {
    final identifier = value?.trim() ?? '';
    if (identifier.isEmpty) return '请输入用户名或邮箱';
    if (identifier.contains('@')) {
      return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(identifier)
          ? null
          : '请输入有效邮箱';
    }
    return _usernamePattern.hasMatch(identifier)
        ? null
        : '用户名需为 5-20 位，首位必须为英文字母，仅含英文、数字或下划线';
  }

  Widget _passwordField(ColorScheme colors) => TextFormField(
    controller: _password,
    focusNode: _passwordFocus,
    obscureText: _obscurePassword,
    textInputAction: TextInputAction.done,
    onChanged: (_) {
      if (_passwordValidated) _formKey.currentState?.validate();
    },
    decoration: InputDecoration(
      hintText: '密码',
      floatingLabelBehavior: FloatingLabelBehavior.never,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      errorMaxLines: 2,
      prefixIcon: Icon(Icons.lock_outline),
      suffixIcon: IconButton(
        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        icon: Icon(
          _obscurePassword
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
        ),
      ),
    ),
    validator: (value) => _passwordValidated && (value?.length ?? 0) < 8
        ? '密码至少需要 8 位'
        : null,
    errorBuilder: _buildShakingErrorText,
  );
}
