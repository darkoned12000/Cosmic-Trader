import 'package:flutter/material.dart';
import 'package:cosmic_trader/core/app_exit.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';
import 'package:cosmic_trader/data/storage/player_storage.dart';
import 'package:cosmic_trader/data/storage/settings_storage.dart';
import 'package:cosmic_trader/screens/game_shell.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  int _step = 0;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _errorMessage;
  int _passwordStrength = 0;

  FactionClass _selectedFaction = FactionClass.trader;
  String _selectedShip = 'Starhawk Skiff';
  bool _unlockAllShips = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsStorage.instance.load();
    if (settings != null) {
      setState(() => _unlockAllShips = settings.unlockAllShips);
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _updatePasswordStrength(String password) {
    int strength = 0;
    if (password.length >= 6) strength++;
    if (password.length >= 10) strength++;
    if (RegExp(r'[A-Z]').hasMatch(password)) strength++;
    if (RegExp(r'[0-9]').hasMatch(password)) strength++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) strength++;
    setState(() => _passwordStrength = strength);
  }

  Color _getStrengthColor() {
    switch (_passwordStrength) {
      case 0:
      case 1:
        return Colors.red;
      case 2:
      case 3:
        return Colors.orange;
      case 4:
      case 5:
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _getStrengthLabel() {
    switch (_passwordStrength) {
      case 0:
        return 'Very Weak';
      case 1:
        return 'Weak';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Strong';
      case 5:
        return 'Very Strong';
      default:
        return '';
    }
  }

  void _validateAndProceed() {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _step = 1);
  }

  Future<void> _register() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final player = await PlayerStorage.instance.register(
        _usernameController.text.trim(),
        _passwordController.text,
        faction: _selectedFaction,
        shipName: _selectedShip,
      );

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
              builder: (context) => GameShell(initialPlayer: player)),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildStepIndicator() {
    return Row(
      children: [
        for (int i = 0; i < 3; i++)
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i <= _step
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey.withValues(alpha: 0.3),
                  ),
                  child: Center(
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        color: i <= _step
                            ? Colors.white
                            : Colors.grey.withValues(alpha: 0.5),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    height: 2,
                    color: i < _step
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey.withValues(alpha: 0.2),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCredentialsStep() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.account_circle_rounded,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 8),
          const Text(
            'Join the Galaxy',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 32),
          TextFormField(
            controller: _usernameController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.person_outline_rounded),
              labelText: 'Username',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please choose a username';
              }
              if (value.trim().length < 3) {
                return 'At least 3 characters required';
              }
              if (value.trim().length > 20) {
                return 'Max 20 characters';
              }
              if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value.trim())) {
                return 'Only letters, numbers, and underscores';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              labelText: 'Password',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
            ),
            onChanged: _updatePasswordStrength,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter a password';
              }
              if (value.length < 6) {
                return 'Password must be at least 6 characters';
              }
              return null;
            },
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Row(
              children: List.generate(5, (index) {
                return Expanded(
                  child: Container(
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: index < _passwordStrength
                          ? _getStrengthColor()
                          : Colors.grey.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              _getStrengthLabel(),
              style: TextStyle(
                color: _getStrengthColor(),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextFormField(
            controller: _confirmController,
            obscureText: _obscureConfirm,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.password_rounded),
              labelText: 'Confirm Password',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirm
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                ),
                onPressed: () {
                  setState(() {
                    _obscureConfirm = !_obscureConfirm;
                  });
                },
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please confirm your password';
              }
              if (value != _passwordController.text) {
                return 'Passwords do not match';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _validateAndProceed,
            child: const Text('CONTINUE',
                style:
                    TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
          ),
        ],
      ),
    );
  }

  Widget _buildFactionStep() {
    final factions =
        FactionClass.values.where((f) => f != FactionClass.pirate).toList();
    return RadioGroup<FactionClass>(
      groupValue: _selectedFaction,
      onChanged: (value) {
        setState(() {
          _selectedFaction = value!;
          _selectedShip = ShipDefinition.getDefaultInterceptor(value).name;
        });
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Choose Your Faction',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          for (final faction in factions)
            Card(
              child: ListTile(
                leading: Icon(
                  faction == FactionClass.duran
                      ? Icons.local_fire_department_rounded
                      : faction == FactionClass.vinari
                          ? Icons.auto_awesome_rounded
                          : Icons.storefront_rounded,
                  color: faction == FactionClass.duran
                      ? Colors.red.shade400
                      : faction == FactionClass.vinari
                          ? Colors.teal.shade400
                          : Colors.amber.shade400,
                ),
                title: Text(
                  faction.displayName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  faction == FactionClass.duran
                      ? 'Warriors of strength and honor'
                      : faction == FactionClass.vinari
                          ? 'Scholars of knowledge and peace'
                          : 'Free traders of the open galaxy',
                ),
                trailing: Radio<FactionClass>(
                  value: faction,
                ),
                selected: _selectedFaction == faction,
                selectedTileColor: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.1),
              ),
            ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _step = 0),
                  child: const Text('BACK'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => setState(() => _step = 2),
                  child: const Text('CONTINUE',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, letterSpacing: 2)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShipStep() {
    final ships = ShipDefinition.getShipsForFaction(_selectedFaction);
    final defaultShip = ShipDefinition.getDefaultInterceptor(_selectedFaction);
    final isLocked = !_unlockAllShips;
    return RadioGroup<String>(
      groupValue: _selectedShip,
      onChanged: (value) {
        setState(() {
          _selectedShip = value!;
        });
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Select Your Ship',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_selectedFaction.name[0].toUpperCase()}${_selectedFaction.name.substring(1)} Fleet',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 14,
            ),
          ),
          if (isLocked) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.shade900.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: Colors.orange.shade700.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline_rounded,
                      size: 16, color: Colors.orange.shade300),
                  const SizedBox(width: 6),
                  Text(
                    'Other ships locked behind milestones',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange.shade300,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          ...ships.map(
            (ship) {
              final isDefault = ship.name == defaultShip.name;
              final locked = isLocked && !isDefault;
              return Card(
                child: ListTile(
                  leading: Icon(
                    ship.shipClass == ShipClassType.interceptor
                        ? Icons.speed_rounded
                        : ship.shipClass == ShipClassType.battleship
                            ? Icons.rocket_launch_rounded
                            : ship.shipClass == ShipClassType.freighter
                                ? Icons.local_shipping_rounded
                                : Icons.star_rounded,
                    color: locked
                        ? Colors.grey.shade600
                        : Theme.of(context).colorScheme.secondary,
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          ship.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: locked ? Colors.grey.shade600 : null,
                          ),
                        ),
                      ),
                      if (locked)
                        Icon(Icons.lock_rounded,
                            size: 16, color: Colors.grey.shade500),
                    ],
                  ),
                  subtitle: Text(
                    locked
                        ? 'Complete milestones to unlock'
                        : '${ship.shipClass.name} | Hull ${ship.maxHullCapacity} | Shields ${ship.shields} | Cargo ${ship.maxCargo}',
                    style: TextStyle(
                      fontSize: 12,
                      color: locked ? Colors.grey.shade500 : null,
                    ),
                  ),
                  trailing: Radio<String>(
                    value: ship.name,
                    enabled: !locked,
                  ),
                  selected: _selectedShip == ship.name,
                  selectedTileColor: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.1),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.red.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red.shade300),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: Colors.red.shade300),
                    ),
                  ),
                ],
              ),
            ),
          if (_errorMessage != null) const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _step = 1),
                  child: const Text('BACK'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _register,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('LAUNCH',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, letterSpacing: 2)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Account'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.power_settings_new_rounded),
            tooltip: 'Exit Game',
            onPressed: quitApplication,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                children: [
                  _buildStepIndicator(),
                  const SizedBox(height: 32),
                  if (_step == 0)
                    _buildCredentialsStep()
                  else if (_step == 1)
                    _buildFactionStep()
                  else
                    _buildShipStep(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
