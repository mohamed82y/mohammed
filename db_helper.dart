import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DBHelper {
  // Singleton so the whole app shares one connection
  static final DBHelper _instance = DBHelper._internal();
  factory DBHelper() => _instance;
  DBHelper._internal();

  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'aseel_lite.db');
    return await openDatabase(
      path,
      version: 1,
      onConfigure: (db) async {
        // Enforce the FOREIGN KEY constraint (off by default in SQLite)
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        balance REAL NOT NULL DEFAULT 0.0
      )
    ''');

    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_id INTEGER NOT NULL,
        amount REAL NOT NULL,
        trans_type TEXT NOT NULL,
        note TEXT,
        date TEXT,
        FOREIGN KEY (account_id) REFERENCES accounts (id)
      )
    ''');
  }

  Future<int> addAccount(String name, String type) async {
    final dbClient = await database;
    return await dbClient.insert('accounts', {
      'name': name,
      'type': type,
      'balance': 0.0,
    });
  }

  Future<List<Map<String, dynamic>>> getAccounts() async {
    final dbClient = await database;
    return await dbClient.query('accounts');
  }

  Future<List<Map<String, dynamic>>> getTransactions() async {
    final dbClient = await database;
    return await dbClient.rawQuery('''
      SELECT transactions.*, accounts.name AS account_name
      FROM transactions
      LEFT JOIN accounts ON transactions.account_id = accounts.id
      ORDER BY transactions.id DESC
    ''');
  }

  /// transType: 'IN' or 'OUT'. Insert + balance update run in one
  /// transaction, so either both happen or neither does.
  Future<void> addTransaction(
      int accountId, double amount, String transType, String note) async {
    final dbClient = await database;

    await dbClient.transaction((txn) async {
      await txn.insert('transactions', {
        'account_id': accountId,
        'amount': amount,
        'trans_type': transType,
        'note': note,
        'date': DateTime.now().toString().substring(0, 10),
      });

      final change = (transType == 'IN') ? amount : -amount;
      await txn.rawUpdate(
        'UPDATE accounts SET balance = balance + ? WHERE id = ?',
        [change, accountId],
      );
    });
  }
}
