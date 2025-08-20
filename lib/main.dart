import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';

const String _defaultConductorId = '123e4567-e89b-12d3-a456-426614174000';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(MyTaskHandler());
}

class MyTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Lógica de inicialização (ex.: log starter.name se necessário)
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    FlutterForegroundTask.updateService(
      notificationTitle: 'TukTuk GPS',
      notificationText:
          'Rastreamento ativo às ${DateFormat.Hms().format(timestamp)}',
    );
    Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high)
        .then((position) {
      _sendDataToSupabase(position, isActive: true);
    }).catchError((error) {
      // Handle error (ex.: log ou save offline)
    });
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await FlutterForegroundTask.clearAllData();
  }
}

Future<void> _sendDataToSupabase(Position position,
    {required bool isActive}) async {
  final supabaseUrl = dotenv.env['SUPABASE_URL'];
  final supabaseKey = dotenv.env['SUPABASE_ANON_KEY'];
  if (supabaseUrl == null || supabaseKey == null) return;
  final payload = jsonEncode({
    'conductor_id': _defaultConductorId,
    'current_latitude': position.latitude,
    'current_longitude': position.longitude,
    'accuracy': position.accuracy,
    'is_active': isActive,
    'updated_at': DateTime.now().toIso8601String(),
  });
  try {
    final response = await http.patch(
      Uri.parse(
          '$supabaseUrl/rest/v1/active_conductors?conductor_id=eq.$_defaultConductorId'),
      headers: {
        'apikey': supabaseKey,
        'Authorization': 'Bearer $supabaseKey',
        'Content-Type': 'application/json',
        'Prefer': 'return=minimal',
      },
      body: payload,
    );
    // Se necessário, chame a função para salvar posição pendente
    // if (response.statusCode < 200 || response.statusCode >= 300) {
    //   await _savePendingPosition(payload);
    // }
  } catch (e) {
    // Se necessário, chame a função para salvar posição pendente
    // await _savePendingPosition(payload);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(const TukTukGpsApp());
}

class TukTukGpsApp extends StatelessWidget {
  const TukTukGpsApp({super.key});
  @override
  Widget build(BuildContext context) {
    final GoRouter router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) {
            final conductorId = state.uri.queryParameters['cid'] ?? '';
            return GpsTrackingScreen(conductorId: conductorId);
          },
        ),
      ],
    );
    return MaterialApp.router(
      title: 'TukTuk GPS Tracker',
      theme: ThemeData(
        primarySwatch: Colors.teal,
        scaffoldBackgroundColor: const Color(0xFFF0F2F5),
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      routerConfig: router,
    );
  }
}

class GpsTrackingScreen extends StatefulWidget {
  final String conductorId;
  const GpsTrackingScreen({super.key, this.conductorId = ''});
  @override
  State<GpsTrackingScreen> createState() => _GpsTrackingScreenState();
}

class _GpsTrackingScreenState extends State<GpsTrackingScreen> {
  Future<void> _saveLastPosition(Position position) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'lastPosition',
        jsonEncode({
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracy': position.accuracy,
          'timestamp': position.timestamp.toIso8601String(),
        }));
    // Otimização: Limite histórico a 100 posições
    _positionsHistory.add(position);
    if (_positionsHistory.length > 100) _positionsHistory.removeAt(0);
  }

  String _statusMessage = 'Parado';
  bool _isTracking = false;
  Position? _lastPosition;
  DateTime? _startTime, _endTime;
  double _totalDistance = 0.0;
  final List<Position> _positionsHistory = [];
  StreamSubscription<Position>? _positionStreamSubscription;
  final LocationSettings _locationSettings = const LocationSettings(
      accuracy: LocationAccuracy.high, distanceFilter: 10);
  bool _hasNetworkError = false;
  bool _hasGpsError = false;
  String _lastErrorMessage = '';
  String get _conductorId =>
      widget.conductorId.isNotEmpty ? widget.conductorId : _defaultConductorId;

  @override
  void initState() {
    super.initState();
    _initForegroundTask();
    _restoreTrackingState();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    super.dispose();
  }

  void _initForegroundTask() {
    FlutterForegroundTask.setTaskHandler(MyTaskHandler());
  }

  Future<void> _restoreTrackingState() async {
    final prefs = await SharedPreferences.getInstance();
    final wasTracking = prefs.getBool('isTracking') ?? false;
    if (wasTracking) {
      final startMillis = prefs.getInt('startTime');
      _startTime = startMillis != null
          ? DateTime.fromMillisecondsSinceEpoch(startMillis)
          : null;
      _totalDistance = prefs.getDouble('totalDistance') ?? 0.0;
      if (mounted) {
        setState(() {
          _isTracking = true;
          _statusMessage = 'Enviando...';
        });
      }
      _startTracking(resume: true);
    }
  }

  void _saveTrackingState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isTracking', _isTracking);
    await prefs.setInt('startTime', _startTime?.millisecondsSinceEpoch ?? 0);
    await prefs.setDouble('totalDistance', _totalDistance);
  }

  Future<void> _checkAndRequestPermissions() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      _showPermissionDialog("Ative o GPS no dispositivo.");
      return;
    }
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
    final status = await Permission.location.request();
    if (status.isGranted) {
      final backgroundStatus = await Permission.locationAlways.request();
      if (backgroundStatus.isGranted) {
        _startTracking();
      } else {
        _showPermissionDialog(
            "Para rastreamento contínuo, a permissão 'Sempre' é necessária.");
      }
    } else {
      _showPermissionDialog("A permissão de localização é essencial.");
    }
  }

  void _showPermissionDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permissão Necessária'),
        content: Text(message),
        actions: [
          TextButton(
              child: const Text('Cancelar'),
              onPressed: () => Navigator.of(context).pop()),
          TextButton(
              child: const Text('Abrir Configurações'),
              onPressed: () {
                openAppSettings();
                Navigator.of(context).pop();
              }),
        ],
      ),
    );
  }

  void _startTracking({bool resume = false}) async {
    if (await FlutterForegroundTask.isRunningService) return;
    if (!resume) {
      if (mounted) {
        setState(() {
          _isTracking = true;
          _statusMessage = 'Enviando...';
          _startTime = DateTime.now();
          _endTime = null;
          _totalDistance = 0.0;
          _positionsHistory.clear();
          _lastPosition = null;
        });
      }
    }
    _saveTrackingState();
    await FlutterForegroundTask.startService(
      notificationTitle: 'TukTuk GPS',
      notificationText: 'A iniciar rastreamento...',
      callback: startCallback,
    );
    _positionStreamSubscription =
        Geolocator.getPositionStream(locationSettings: _locationSettings)
            .listen(
      (Position position) {
        if (!mounted) return;
        setState(() {
          _lastPosition = position;
          if (_positionsHistory.isNotEmpty) {
            _totalDistance += Geolocator.distanceBetween(
                _positionsHistory.last.latitude,
                _positionsHistory.last.longitude,
                position.latitude,
                position.longitude);
          }
          _positionsHistory.add(position);
          if (_hasGpsError) {
            _hasGpsError = false;
            _lastErrorMessage = '';
          }
        });
        _saveLastPosition(position);
        _sendDataToSupabase(position, isActive: true);
      },
      onError: (error) => _showError('Erro de GPS: $error', isNetwork: false),
    );
  }

  void _stopTracking() async {
    _positionStreamSubscription?.cancel();
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
    if (mounted) {
      setState(() {
        _isTracking = false;
        _statusMessage = 'Tracking finalizado';
        _endTime = DateTime.now();
      });
    }
    if (_lastPosition != null) {
      _sendDataToSupabase(_lastPosition!, isActive: false);
    }
    _saveTrackingState();
  }

  Future<void> _sendDataToSupabase(Position position,
      {required bool isActive}) async {
    await _saveLastPosition(position);
    final supabaseUrl = dotenv.env['SUPABASE_URL'];
    final supabaseKey = dotenv.env['SUPABASE_ANON_KEY'];
    if (supabaseUrl == null || supabaseKey == null) {
      _showError("Chaves da API não encontradas.");
      return;
    }
    final payload = jsonEncode({
      'conductor_id': _conductorId,
      'current_latitude': position.latitude,
      'current_longitude': position.longitude,
      'accuracy': position.accuracy,
      'is_active': isActive,
      'updated_at': DateTime.now().toIso8601String(),
    });
    try {
      final response = await http.patch(
        Uri.parse(
            '$supabaseUrl/rest/v1/active_conductors?conductor_id=eq.$_conductorId'),
        headers: {
          'apikey': supabaseKey,
          'Authorization': 'Bearer $supabaseKey',
          'Content-Type': 'application/json',
          'Prefer': 'return=minimal',
        },
        body: payload,
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (_hasNetworkError && mounted) {
          setState(() {
            _hasNetworkError = false;
            _lastErrorMessage = '';
          });
        }
        await _syncPendingPositions();
      } else {
        _showError('Falha ao enviar: ${response.statusCode}');
        _savePendingPosition(payload);
      }
    } catch (e) {
      _showError('Sem internet. Dados guardados.');
      _savePendingPosition(payload);
    }
  }

  Future<void> _savePendingPosition(String payload) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getStringList('pendingPositions') ?? [];
    pending.add(payload);
    await prefs.setStringList('pendingPositions', pending);
  }

  Future<void> _syncPendingPositions() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getStringList('pendingPositions') ?? [];
    if (pending.isEmpty) return;
    final successfullySynced = <String>[];
    for (final payload in pending) {
      try {
        final response = await http.patch(
          Uri.parse(
              '${dotenv.env['SUPABASE_URL']}/rest/v1/active_conductors?conductor_id=eq.$_conductorId'),
          headers: {
            'apikey': dotenv.env['SUPABASE_ANON_KEY']!,
            'Authorization': 'Bearer ${dotenv.env['SUPABASE_ANON_KEY']!}',
            'Content-Type': 'application/json',
            'Prefer': 'return=minimal',
          },
          body: payload,
        );
        if (response.statusCode >= 200 && response.statusCode < 300) {
          successfullySynced.add(payload);
        }
      } catch (e) {}
    }
    if (successfullySynced.isNotEmpty) {
      pending.removeWhere((p) => successfullySynced.contains(p));
      await prefs.setStringList('pendingPositions', pending);
    }
  }

  void _showError(String message, {bool isNetwork = true}) {
    if (!mounted) return;
    setState(() {
      _hasNetworkError = isNetwork;
      _hasGpsError = !isNetwork;
      _lastErrorMessage = message;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Colors.red.shade700,
    ));
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    return "$hours h $minutes min";
  }

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('GPS TukTuk Milfontes'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        extendBodyBehindAppBar: true,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/images/tuktuk_bg.jpg',
              fit: BoxFit.cover,
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildStatusCard(),
                    const SizedBox(height: 20),
                    if (!_isTracking && _endTime != null)
                      _buildTripSummaryCard()
                    else
                      _buildLocationDetailsCard(),
                    const Spacer(),
                    _buildActionButtons(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    final statusColor =
        _isTracking ? Colors.green.shade700 : Colors.red.shade700;
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_isTracking ? Icons.gps_fixed : Icons.gps_off,
                    color: statusColor, size: 28),
                const SizedBox(width: 10),
                Text(
                  'Status: $_statusMessage',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: statusColor),
                ),
              ],
            ),
            if (_hasNetworkError || _hasGpsError)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  _lastErrorMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red.shade700),
                ),
              ),
            const SizedBox(height: 8),
            const Text('👤 Condutor: TukTuk 01',
                style: TextStyle(fontSize: 16, color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationDetailsCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🗺️ Última localização:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Text(
                'Latitude: ${_lastPosition?.latitude.toStringAsFixed(5) ?? '--'}'),
            const SizedBox(height: 4),
            Text(
                'Longitude: ${_lastPosition?.longitude.toStringAsFixed(5) ?? '--'}'),
            const SizedBox(height: 4),
            Text(
                'Precisão: ${_lastPosition != null ? '${_lastPosition!.accuracy.toStringAsFixed(1)}m' : '--'}'),
            const SizedBox(height: 12),
            const Align(
              alignment: Alignment.centerRight,
              child: Text('Intervalo: ~10s / 10m',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildTripSummaryCard() {
    if (_startTime == null || _endTime == null) return const SizedBox.shrink();
    final duration = _endTime!.difference(_startTime!);
    return Card(
      elevation: 4,
      color: Colors.teal.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('📊 Resumo da Viagem',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal)),
            const Divider(),
            _buildSummaryRow('🕒 Início:',
                DateFormat('dd/MM/yyyy HH:mm').format(_startTime!)),
            _buildSummaryRow('🕒 Término:',
                DateFormat('dd/MM/yyyy HH:mm').format(_endTime!)),
            _buildSummaryRow('⏳ Tempo ligado:', _formatDuration(duration)),
            _buildSummaryRow('📏 Distância:',
                '${(_totalDistance / 1000).toStringAsFixed(2)} km'),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(value, style: const TextStyle(fontSize: 15)),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return ElevatedButton.icon(
      icon: Icon(
          _isTracking ? Icons.stop_circle_outlined : Icons.play_circle_outline),
      label: Text(_isTracking
          ? 'Desligar Tracking'
          : (_endTime == null ? 'Ligar Tracking' : 'Ligar Novamente')),
      onPressed: _isTracking ? _stopTracking : _checkAndRequestPermissions,
      style: ElevatedButton.styleFrom(
        backgroundColor:
            _isTracking ? Colors.red.shade600 : Colors.green.shade600,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }
}
