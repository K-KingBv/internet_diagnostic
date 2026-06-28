import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Diagnóstico de Red',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const DiagnosticoScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class DiagnosticoScreen extends StatefulWidget {
  const DiagnosticoScreen({super.key});

  @override
  State<DiagnosticoScreen> createState() => _DiagnosticoScreenState();
}

class _DiagnosticoScreenState extends State<DiagnosticoScreen> {
  bool _isRunning = false;
  String _resultadoGeneral = "Presiona el botón para iniciar el diagnóstico.";
  Color _colorGeneral = Colors.grey;
  List<Map<String, dynamic>> _resultados = [];

  // IPs por defecto
  final String _gateway1 = '192.168.1.1';
  final String _gateway2 = '192.168.0.1';
  final String _dns1 = '8.8.8.8';
  final String _dns2 = '1.1.1.1';

  // ------------------- MOTOR DE DIAGNÓSTICO -------------------

  Future<void> runDiagnostico() async {
    setState(() {
      _isRunning = true;
      _resultados = [];
      _resultadoGeneral = "Ejecutando pruebas...";
      _colorGeneral = Colors.orange;
    });

    // 1. Verificar conectividad física (WiFi/Data)
    var connectivityResult = await Connectivity().checkConnectivity();
    bool tieneRed = connectivityResult != ConnectivityResult.none;

    if (!tieneRed) {
      setState(() {
        _resultadoGeneral = "❌ No tienes conexión de red activa (WiFi o datos).";
        _colorGeneral = Colors.red;
        _isRunning = false;
      });
      return;
    }

    // 2. Buscar el Gateway (router) que responde
    String? gatewayActivo;
    try {
      for (var ip in [_gateway1, _gateway2]) {
        var ping = await _tcpPing(ip, 80, count: 2);
        if (ping['success'] > 0) {
          gatewayActivo = ip;
          break;
        }
      }
    } catch (e) {}

    // Si no hay gateway, el problema es el router o el WiFi
    if (gatewayActivo == null) {
      _agregarResultado("Router (WiFi/Cable)", "❌ No responde", "No se pudo contactar con el router local.", Colors.red);
      setState(() {
        _resultadoGeneral =
            "⚠️ PROBLEMA GRAVE: No se detecta el router. Revisa el cable, el WiFi o reinicia el router.";
        _colorGeneral = Colors.red;
        _isRunning = false;
      });
      return;
    }

    _agregarResultado("Router ($gatewayActivo)", "✅ Conectado", "El router responde correctamente.", Colors.green);

    // 3. Prueba de Ping (Latencia) al Router (más preciso)
    var pingRouter = await _tcpPing(gatewayActivo, 80, count: 5);
    String routerLatencia = _parseLatencia(pingRouter);
    String routerPerdida = "${pingRouter['loss']}%";
    bool routerOk = pingRouter['loss'] < 30 && pingRouter['avg'] < 100;
    _agregarResultado(
      "Latencia al Router",
      routerOk ? "✅ $routerLatencia" : "⚠️ $routerLatencia",
      "Pérdida: $routerPerdida. ${routerOk ? 'Excelente.' : 'Alta latencia o pérdida.'}",
      routerOk ? Colors.green : Colors.orange,
    );

    // 4. Prueba de Ping a Internet (8.8.8.8)
    var pingInternet = await _tcpPing(_dns1, 80, count: 5);
    String internetLatencia = _parseLatencia(pingInternet);
    String internetPerdida = "${pingInternet['loss']}%";
    bool internetOk = pingInternet['loss'] < 20 && pingInternet['avg'] < 150;

    // Si falla a 8.8.8.8, probamos con 1.1.1.1
    if (pingInternet['success'] == 0) {
      var pingInternet2 = await _tcpPing(_dns2, 443, count: 5);
      if (pingInternet2['success'] > 0) {
        pingInternet = pingInternet2;
        internetLatencia = _parseLatencia(pingInternet);
        internetPerdida = "${pingInternet['loss']}%";
        internetOk = pingInternet['loss'] < 20 && pingInternet['avg'] < 150;
      }
    }

    _agregarResultado(
      "Latencia a Internet (${pingInternet['host']})",
      internetOk ? "✅ $internetLatencia" : "⚠️ $internetLatencia",
      "Pérdida: $internetPerdida. ${internetOk ? 'Conexión estable.' : 'Problemas con el ISP.'}",
      internetOk ? Colors.green : Colors.orange,
    );

    // 5. Prueba de Resolución DNS
    bool dnsOk = false;
    String dnsTiempo = "0 ms";
    try {
      var start = DateTime.now();
      var lookup = await InternetAddress.lookup('google.com');
      var end = DateTime.now();
      var diff = end.difference(start);
      dnsTiempo = "${diff.inMilliseconds} ms";
      dnsOk = lookup.isNotEmpty && diff.inMilliseconds < 500;
    } catch (e) {
      dnsOk = false;
    }

    _agregarResultado(
      "Resolución DNS (google.com)",
      dnsOk ? "✅ $dnsTiempo" : "❌ Falló",
      dnsOk ? "DNS funciona rápido." : "El DNS no responde. Cambia a 8.8.8.8.",
      dnsOk ? Colors.green : Colors.red,
    );

    // 6. Prueba de Velocidad (Descarga pequeña)
    String velocidad = "0 Mbps";
    bool velocidadOk = false;
    try {
      var start = DateTime.now();
      var response = await http.get(Uri.parse('https://www.google.com/favicon.ico'));
      var end = DateTime.now();
      var bytes = response.bodyBytes.length;
      var time = end.difference(start).inMilliseconds / 1000;
      if (time > 0 && bytes > 0) {
        double kbps = (bytes * 8) / (time * 1024);
        velocidad = "${(kbps / 1024).toStringAsFixed(2)} Mbps";
        velocidadOk = kbps > 100; // más de 100 Kbps ≈ 0.8 Mbps mínimo aceptable
      }
    } catch (e) {
      velocidad = "Error";
    }

    _agregarResultado(
      "Velocidad de descarga",
      velocidadOk ? "✅ $velocidad" : "⚠️ $velocidad",
      velocidadOk ? "Velocidad aceptable." : "Descarga lenta o fallida.",
      velocidadOk ? Colors.green : Colors.orange,
    );

    // ------------------- DIAGNÓSTICO FINAL -------------------
    // Lógica para la conclusión final:
    if (!internetOk && !routerOk) {
      _resultadoGeneral =
          "🚨 PROBLEMA CRÍTICO: Tu router e Internet fallan. Reinicia el router y revisa los cables. Si persiste, llama a tu ISP.";
      _colorGeneral = Colors.red;
    } else if (!internetOk) {
      _resultadoGeneral =
          "📡 PROBLEMA CON TU ISP: El router funciona, pero no hay salida a Internet. Contacta con tu proveedor de servicios.";
      _colorGeneral = Colors.orange;
    } else if (!routerOk) {
      _resultadoGeneral =
          "📶 PROBLEMA CON EL ROUTER: Internet llega, pero tu red local (WiFi/cable) tiene problemas. Acércate al router o reinícialo.";
      _colorGeneral = Colors.orange;
    } else if (!dnsOk) {
      _resultadoGeneral =
          "🌐 PROBLEMA DE DNS: La conexión funciona, pero no resuelve nombres. Prueba a configurar los DNS manualmente a 8.8.8.8.";
      _colorGeneral = Colors.orange;
    } else if (pingInternet['avg'] > 150) {
      _resultadoGeneral =
          "🐢 INTERNET LENTO: Tu conexión está muy saturada o tienes alta latencia (>150ms). Revisa si hay descargas activas.";
      _colorGeneral = Colors.orange;
    } else {
      _resultadoGeneral =
          "✅ ¡TODO PERFECTO! Tu conexión a Internet funciona correctamente. Disfruta de la navegación.";
      _colorGeneral = Colors.green;
    }

    // Añadir un resumen de la IP del router encontrado
    _agregarResultado(
        "IP del Router detectada",
        gatewayActivo,
        "Si usas otro router, cámbialo en el código.",
        Colors.blue);

    setState(() {
      _isRunning = false;
    });
  }

  // ------------------- FUNCIONES DE PRUEBA (TCP Ping) -------------------

  Future<Map<String, dynamic>> _tcpPing(String host, int port, {int count = 4}) async {
    List<double> tiempos = [];
    int success = 0;
    int loss = 0;

    for (int i = 0; i < count; i++) {
      try {
        var start = DateTime.now();
        // Intenta conectar al puerto (80 o 443)
        Socket socket = await Socket.connect(host, port, timeout: const Duration(seconds: 3));
        var end = DateTime.now();
        double ms = end.difference(start).inMilliseconds.toDouble();
        tiempos.add(ms);
        success++;
        await socket.close();
      } catch (e) {
        loss++;
      }
    }

    double min = tiempos.isEmpty ? 0 : tiempos.reduce((a, b) => a < b ? a : b);
    double max = tiempos.isEmpty ? 0 : tiempos.reduce((a, b) => a > b ? a : b);
    double avg = tiempos.isEmpty ? 0 : tiempos.reduce((a, b) => a + b) / tiempos.length;

    return {
      'host': host,
      'port': port,
      'success': success,
      'loss': (loss / count * 100).round(),
      'min': min,
      'max': max,
      'avg': avg,
      'raw': tiempos,
    };
  }

  String _parseLatencia(Map<String, dynamic> result) {
    if (result['success'] == 0) return "Sin respuesta";
    return "min: ${result['min']}ms / máx: ${result['max']}ms / prom: ${result['avg'].toStringAsFixed(0)}ms";
  }

  void _agregarResultado(String titulo, String estado, String detalle, Color color) {
    setState(() {
      _resultados.add({
        'titulo': titulo,
        'estado': estado,
        'detalle': detalle,
        'color': color,
      });
    });
  }

  // ------------------- INTERFAZ GRÁFICA (UI) -------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🔍 Diagnóstico de Internet'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Botón principal
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isRunning ? null : runDiagnostico,
                icon: _isRunning
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(_isRunning ? 'Probando...' : 'Iniciar Diagnóstico'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Conclusión General
            Card(
              color: _colorGeneral.withOpacity(0.15),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(
                      _colorGeneral == Colors.green
                          ? Icons.check_circle
                          : _colorGeneral == Colors.red
                              ? Icons.error
                              : Icons.warning,
                      color: _colorGeneral,
                      size: 32,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        _resultadoGeneral,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _colorGeneral == Colors.grey
                              ? Colors.black87
                              : _colorGeneral,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Lista de resultados detallados
            Expanded(
              child: ListView.builder(
                itemCount: _resultados.length,
                itemBuilder: (context, index) {
                  var item = _resultados[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: Icon(
                        Icons.circle,
                        color: item['color'],
                        size: 14,
                      ),
                      title: Text(
                        item['titulo'],
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(item['detalle']),
                      trailing: Text(
                        item['estado'],
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: item['color'],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}