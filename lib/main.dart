import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math';

class LocalDatabase {
  static Future<SharedPreferences> get _prefs async => await SharedPreferences.getInstance();

  static Future<List<Map<String, dynamic>>> getAll(String table) async {
    final prefs = await _prefs;
    final data = prefs.getString(table);
    if (data == null) return [];
    return List<Map<String, dynamic>>.from(jsonDecode(data));
  }

  static Future<void> saveAll(String table, List<Map<String, dynamic>> items) async {
    final prefs = await _prefs;
    await prefs.setString(table, jsonEncode(items));
  }

  static Future<void> insert(String table, Map<String, dynamic> item) async {
    final items = await getAll(table);
    item['id'] = DateTime.now().millisecondsSinceEpoch.toString();
    item['createdAt'] = DateTime.now().toIso8601String();
    items.add(item);
    await saveAll(table, items);
  }

  static Future<void> update(String table, String id, Map<String, dynamic> item) async {
    final items = await getAll(table);
    final index = items.indexWhere((e) => e['id'] == id);
    if (index != -1) { item['id'] = id; items[index] = item; await saveAll(table, items); }
  }

  static Future<void> delete(String table, String id) async {
    final items = await getAll(table);
    items.removeWhere((e) => e['id'] == id);
    await saveAll(table, items);
  }
}

enum LicenseStatus { trial, licensed, expired }

class LicenseManager {
  static const String _firstRunKey = 'app_first_run';
  static const String _licenseKey = 'app_license';
  static const int trialDays = 30;

  static Future<LicenseStatus> checkLicense() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_licenseKey) != null) return LicenseStatus.licensed;
    final firstRun = prefs.getString(_firstRunKey);
    if (firstRun == null) {
      await prefs.setString(_firstRunKey, DateTime.now().toIso8601String());
      return LicenseStatus.trial;
    }
    final startDate = DateTime.parse(firstRun);
    final daysUsed = DateTime.now().difference(startDate).inDays;
    return daysUsed < trialDays ? LicenseStatus.trial : LicenseStatus.expired;
  }

  static Future<int> getRemainingDays() async {
    final prefs = await SharedPreferences.getInstance();
    final firstRun = prefs.getString(_firstRunKey);
    if (firstRun == null) return trialDays;
    final startDate = DateTime.parse(firstRun);
    final daysUsed = DateTime.now().difference(startDate).inDays;
    return (trialDays - daysUsed).clamp(0, trialDays);
  }

  static Future<bool> activate(String key) async {
    final cleaned = key.trim().toUpperCase();
    if (cleaned.length == 19 && cleaned.contains('-')) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_licenseKey, cleaned);
      return true;
    }
    return false;
  }
}

class TrialBanner extends StatelessWidget {
  final int daysRemaining;
  const TrialBanner({super.key, required this.daysRemaining});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      color: daysRemaining <= 2 ? Colors.red : Colors.orange,
      child: Text('Teste: ' + daysRemaining.toString() + ' dias restantes', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }
}

class LicenseExpiredScreen extends StatefulWidget {
  const LicenseExpiredScreen({super.key});
  @override
  State<LicenseExpiredScreen> createState() => _LicenseExpiredScreenState();
}

class _LicenseExpiredScreenState extends State<LicenseExpiredScreen> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;
  Future<void> _activate() async {
    setState(() { _loading = true; _error = null; });
    final ok = await LicenseManager.activate(_ctrl.text);
    if (ok && mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const RestartApp()));
    else if (mounted) setState(() { _error = 'Chave invalida'; _loading = false; });
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.red.shade800, Colors.red.shade600])), child: SafeArea(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.lock, size: 80, color: Colors.white), const SizedBox(height: 24), const Text('Periodo Expirado', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)), const SizedBox(height: 32), TextField(controller: _ctrl, decoration: InputDecoration(labelText: 'Chave', filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), errorText: _error), maxLength: 19), const SizedBox(height: 16), ElevatedButton(onPressed: _loading ? null : _activate, child: _loading ? const CircularProgressIndicator() : const Text('Ativar'))])))));
  }
}

class RestartApp extends StatelessWidget {
  const RestartApp({super.key});
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(future: Future.wait([LicenseManager.checkLicense(), LicenseManager.getRemainingDays()]), builder: (context, snap) {
      if (!snap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      return MyApp(licenseStatus: snap.data![0] as LicenseStatus, remainingDays: snap.data![1] as int);
    });
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final status = await LicenseManager.checkLicense();
  final days = await LicenseManager.getRemainingDays();
  runApp(MyApp(licenseStatus: status, remainingDays: days));
}

class MyApp extends StatelessWidget {
  final LicenseStatus licenseStatus;
  final int remainingDays;
  const MyApp({super.key, required this.licenseStatus, required this.remainingDays});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.dark(primary: Colors.purple, secondary: Colors.purpleAccent),
        scaffoldBackgroundColor: const Color(0xFF1a1a2e),
        cardColor: const Color(0xFF16213e),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF0f0f1a)),
      ),
      home: licenseStatus == LicenseStatus.expired ? const LicenseExpiredScreen() : HomeScreen(licenseStatus: licenseStatus, remainingDays: remainingDays),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final LicenseStatus licenseStatus;
  final int remainingDays;
  const HomeScreen({super.key, required this.licenseStatus, required this.remainingDays});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final PageController _pageController = PageController();
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Caos no Buffet'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          if (widget.licenseStatus == LicenseStatus.trial)
            TrialBanner(daysRemaining: widget.remainingDays),
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (index) => setState(() => _currentIndex = index),
              children: const [
                GameScreen(),
                RecordsScreen(),
                SettingsScreen(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() => _currentIndex = index);
          _pageController.animateToPage(index, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.games), label: 'Jogo'),
          BottomNavigationBarItem(icon: Icon(Icons.list), label: 'Recordes'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Config'),
        ],
      ),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  Timer? _gameTimer;
  double _comida = 100.0;
  double _paciencia = 100.0;
  double _limpeza = 100.0;
  int _pontos = 0;
  bool _gameRunning = false;
  bool _gameOver = false;
  String? _eventoAtivo;
  Timer? _eventoTimer;
  final Random _random = Random();

  final List<String> _eventos = [
    'Tio do Pavê contando piadas!',
    'Criança derrubando comida!',
    'Fila enorme se formando!',
    'Cliente reclamando!',
    'Vazamento na cozinha!'
  ];

  @override
  void dispose() {
    _gameTimer?.cancel();
    _eventoTimer?.cancel();
    super.dispose();
  }

  void _iniciarJogo() {
    setState(() {
      _comida = 100.0;
      _paciencia = 100.0;
      _limpeza = 100.0;
      _pontos = 0;
      _gameRunning = true;
      _gameOver = false;
      _eventoAtivo = null;
    });

    _gameTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (!mounted) return;
      setState(() {
        _comida = (_comida - 0.8).clamp(0, 100);
        _paciencia = (_paciencia - 0.6).clamp(0, 100);
        _limpeza = (_limpeza - 0.4).clamp(0, 100);
        _pontos += 1;
      });

      if (_comida <= 0 || _paciencia <= 0 || _limpeza <= 0) {
        _fimDeJogo();
      }

      if (_random.nextInt(100) < 3) {
        _ativarEvento();
      }
    });
  }

  void _ativarEvento() {
    if (_eventoAtivo != null) return;
    
    final evento = _eventos[_random.nextInt(_eventos.length)];
    setState(() => _eventoAtivo = evento);

    _eventoTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        switch (evento) {
          case 'Tio do Pavê contando piadas!':
            _paciencia = (_paciencia - 15).clamp(0, 100);
            break;
          case 'Criança derrubando comida!':
            _limpeza = (_limpeza - 20).clamp(0, 100);
            break;
          case 'Fila enorme se formando!':
            _paciencia = (_paciencia - 25).clamp(0, 100);
            break;
          case 'Cliente reclamando!':
            _paciencia = (_paciencia - 20).clamp(0, 100);
            break;
          case 'Vazamento na cozinha!':
            _limpeza = (_limpeza - 30).clamp(0, 100);
            break;
        }
        _eventoAtivo = null;
      });
    });
  }

  void _fimDeJogo() async {
    _gameTimer?.cancel();
    _eventoTimer?.cancel();
    setState(() {
      _gameRunning = false;
      _gameOver = true;
    });

    await LocalDatabase.insert('recordes', {
      'pontos': _pontos,
      'data': DateTime.now().toString(),
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Game Over! Pontuação: $_pontos'))
      );
    }
  }

  void _resolverComida() {
    if (!_gameRunning) return;
    setState(() => _comida = (_comida + 30).clamp(0, 100));
  }

  void _resolverPaciencia() {
    if (!_gameRunning) return;
    setState(() => _paciencia = (_paciencia + 25).clamp(0, 100));
  }

  void _resolverLimpeza() {
    if (!_gameRunning) return;
    setState(() => _limpeza = (_limpeza + 35).clamp(0, 100));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text('Pontos: $_pontos', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  _buildResourceBar('Comida', _comida, Colors.orange),
                  const SizedBox(height: 8),
                  _buildResourceBar('Paciência', _paciencia, Colors.blue),
                  const SizedBox(height: 8),
                  _buildResourceBar('Limpeza', _limpeza, Colors.green),
                ],
              ),
            ),
          ),
          
          if (_eventoAtivo != null)
            Card(
              color: Colors.red.shade800,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.yellow),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_eventoAtivo!, style: const TextStyle(fontWeight: FontWeight.bold))),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 20),
          
          if (!_gameRunning)
            ElevatedButton(
              onPressed: _iniciarJogo,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
              ),
              child: Text(_gameOver ? 'Jogar Novamente' : 'Iniciar Jogo', style: const TextStyle(fontSize: 18)),
            ),

          if (_gameRunning) ...[
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  GestureDetector(
                    onTap: _resolverComida,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: const Offset(2, 2))],
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.restaurant, size: 40, color: Colors.white),
                          SizedBox(height: 8),
                          Text('Repor\nComida', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      GestureDetector(
                        onTap: _resolverPaciencia,
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: const Offset(2, 2))],
                          ),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.people, size: 40, color: Colors.white),
                              SizedBox(height: 8),
                              Text('Acalmar\nClientes', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _resolverLimpeza,
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: const Offset(2, 2))],
                          ),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.cleaning_services, size: 40, color: Colors.white),
                              SizedBox(height: 8),
                              Text('Limpar\nChão', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResourceBar(String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${value.toInt()}%'),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: value / 100,
          backgroundColor: Colors.grey.shade700,
          valueColor: AlwaysStoppedAnimation<Color>(color),
          minHeight: 8,
        ),
      ],
    );
  }
}

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key});
  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  List<Map<String, dynamic>> _recordes = [];

  @override
  void initState() {
    super.initState();
    _carregarRecordes();
  }

  Future<void> _carregarRecordes() async {
    final dados = await LocalDatabase.getAll('recordes');
    dados.sort((a, b) => (b['pontos'] as int).compareTo(a['pontos'] as int));
    setState(() => _recordes = dados);
  }

  Future<void> _limparRecordes() async {
    await LocalDatabase.saveAll('recordes', []);
    _carregarRecordes();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Recordes limpos!'))
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Melhores Pontuações', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              ElevatedButton(
                onPressed: _limparRecordes,
                child: const Text('Limpar'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _recordes.isEmpty
                ? const Center(child: Text('Nenhum recorde ainda!'))
                : ListView.builder(
                    itemCount: _recordes.length,
                    itemBuilder: (context, index) {
                      final recorde = _recordes[index];
                      final data = DateTime.parse(recorde['data']);
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text('${index + 1}'),
                          ),
                          title: Text('${recorde['pontos']} pontos'),
                          subtitle: Text('${data.day}/${data.month}/${data.year} ${data.hour}:${data.minute.toString().padLeft(2, '0')}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () async {
                              await LocalDatabase.delete('recordes', recorde['id']);
                              _carregarRecordes();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Recorde excluído!'))
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<Map<String, dynamic>> _configuracoes = [];
  final _nomeCtrl = TextEditingController();
  final _valorCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoes();
  }

  Future<void> _carregarConfiguracoes() async {
    final dados = await LocalDatabase.getAll('configuracoes');
    setState(() => _configuracoes = dados);
  }

  void _mostrarFormulario([Map<String, dynamic>? config]) {
    if (config != null) {
      _nomeCtrl.text = config['nome'];
      _valorCtrl.text = config['valor'];
    } else {
      _nomeCtrl.clear();
      _valorCtrl.clear();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          top: 16,
          left: 16,
          right: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(config == null ? 'Nova Configuração' : 'Editar Configuração', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _nomeCtrl,
              decoration: const InputDecoration(
                labelText: 'Nome',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _valorCtrl,
              decoration: const InputDecoration(
                labelText: 'Valor',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () => _salvarConfiguracao(config),
                  child: const Text('Salvar'),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _salvarConfiguracao(Map<String, dynamic>? config) async {
    if (_nomeCtrl.text.trim().isEmpty || _valorCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha todos os campos!'))
      );
      return;
    }

    final dados = {
      'nome': _nomeCtrl.text.trim(),
      'valor': _valorCtrl.text.trim(),
    };

    if (config == null) {
      await LocalDatabase.insert('configuracoes', dados);
    } else {
      await LocalDatabase.update('configuracoes', config['id'], dados);
    }

    Navigator.pop(context);
    _carregarConfiguracoes();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(config == null ? 'Configuração criada!' : 'Configuração atualizada!'))
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Configurações do Jogo', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Expanded(
              child: _configuracoes.isEmpty
                  ? const Center(child: Text('Nenhuma configuração criada'))
                  : ListView.builder(
                      itemCount: _configuracoes.length,
                      itemBuilder: (context, index) {
                        final config = _configuracoes[index];
                        return Card(
                          child: ListTile(
                            title: Text(config['nome']),
                            subtitle: Text(config['valor']),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () => _mostrarFormulario(config),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete),
                                  onPressed: () async {
                                    await LocalDatabase.delete('configuracoes', config['id']);
                                    _carregarConfiguracoes();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Configuração excluída!'))
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _mostrarFormulario(),
        child: const Icon(Icons.add),
      ),
    );
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _valorCtrl.dispose();
    super.dispose();
  }
}