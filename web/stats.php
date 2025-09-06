<?php
/**
 * WireGuard Obfuscation Setup - Web Statistics Dashboard
 * Отображение статистики подключений и состояния сервера
 */

// Настройки
$wg_interface = 'wg0';
$config_path = '/var/wireguard';
$refresh_interval = 5; // секунд

// Функция выполнения команд
function exec_command($command) {
    $output = [];
    $return_var = 0;
    exec($command . ' 2>&1', $output, $return_var);
    return [
        'output' => implode("\n", $output),
        'success' => $return_var === 0
    ];
}

// Получение статистики WireGuard
function get_wg_stats() {
    global $wg_interface;

    $result = exec_command("wg show $wg_interface");
    if (!$result['success']) {
        return ['error' => 'WireGuard interface not found or not running'];
    }

    $lines = explode("\n", $result['output']);
    $stats = [
        'interface' => $wg_interface,
        'peers' => [],
        'server_info' => []
    ];

    $current_peer = null;

    foreach ($lines as $line) {
        $line = trim($line);
        if (empty($line)) continue;

        if (strpos($line, 'interface:') === 0) {
            $stats['server_info']['interface'] = trim(substr($line, 10));
        } elseif (strpos($line, 'public key:') === 0) {
            $stats['server_info']['public_key'] = trim(substr($line, 11));
        } elseif (strpos($line, 'private key:') === 0) {
            $stats['server_info']['private_key'] = '(hidden)';
        } elseif (strpos($line, 'listening port:') === 0) {
            $stats['server_info']['port'] = trim(substr($line, 15));
        } elseif (strpos($line, 'peer:') === 0) {
            $current_peer = trim(substr($line, 5));
            $stats['peers'][$current_peer] = [
                'public_key' => $current_peer,
                'endpoint' => 'Unknown',
                'allowed_ips' => 'Unknown',
                'latest_handshake' => 'Never',
                'transfer_rx' => 0,
                'transfer_tx' => 0,
                'status' => 'Offline'
            ];
        } elseif ($current_peer && strpos($line, 'endpoint:') === 0) {
            $stats['peers'][$current_peer]['endpoint'] = trim(substr($line, 9));
        } elseif ($current_peer && strpos($line, 'allowed ips:') === 0) {
            $stats['peers'][$current_peer]['allowed_ips'] = trim(substr($line, 12));
        } elseif ($current_peer && strpos($line, 'latest handshake:') === 0) {
            $handshake = trim(substr($line, 17));
            $stats['peers'][$current_peer]['latest_handshake'] = $handshake;

            // Определяем статус на основе времени последнего handshake
            if ($handshake !== 'Never') {
                $stats['peers'][$current_peer]['status'] = 'Online';
            }
        } elseif ($current_peer && strpos($line, 'transfer:') === 0) {
            $transfer = trim(substr($line, 9));
            $parts = explode(' received, ', $transfer);
            if (count($parts) == 2) {
                $stats['peers'][$current_peer]['transfer_rx'] = trim($parts[0]);
                $stats['peers'][$current_peer]['transfer_tx'] = trim(str_replace(' sent', '', $parts[1]));
            }
        }
    }

    return $stats;
}

// Получение информации о клиентах из конфигов
function get_client_info() {
    global $config_path;

    $clients = [];
    $config_files = glob("$config_path/*.conf");

    foreach ($config_files as $file) {
        if (basename($file) === 'wg0.conf') continue; // Пропускаем серверный конфиг

        $content = file_get_contents($file);
        $client_name = basename($file, '.conf');

        // Извлекаем информацию из конфига
        preg_match('/# Client: (.+)/', $content, $name_match);
        preg_match('/PublicKey = (.+)/', $content, $key_match);
        preg_match('/AllowedIPs = (.+)/', $content, $ip_match);

        $clients[$client_name] = [
            'name' => $name_match[1] ?? $client_name,
            'public_key' => $key_match[1] ?? 'Unknown',
            'allowed_ips' => $ip_match[1] ?? 'Unknown',
            'config_file' => basename($file),
            'created' => date('Y-m-d H:i:s', filemtime($file))
        ];
    }

    return $clients;
}

// Получение статистики системы
function get_system_stats() {
    $stats = [];

    // Uptime
    $uptime_result = exec_command("cat /proc/uptime");
    if ($uptime_result['success']) {
        $uptime_seconds = floatval(explode(' ', $uptime_result['output'])[0]);
        $stats['uptime'] = gmdate("H:i:s", $uptime_seconds);
    }

    // Load average
    $load_result = exec_command("cat /proc/loadavg");
    if ($load_result['success']) {
        $load_parts = explode(' ', $load_result['output']);
        $stats['load_average'] = $load_parts[0] . ' ' . $load_parts[1] . ' ' . $load_parts[2];
    }

    // Memory usage
    $mem_result = exec_command("free -m");
    if ($mem_result['success']) {
        $lines = explode("\n", $mem_result['output']);
        if (isset($lines[1])) {
            $mem_parts = preg_split('/\s+/', $lines[1]);
            $stats['memory_total'] = $mem_parts[1] . ' MB';
            $stats['memory_used'] = $mem_parts[2] . ' MB';
            $stats['memory_free'] = $mem_parts[3] . ' MB';
        }
    }

    return $stats;
}

// Получение всех данных
$wg_stats = get_wg_stats();
$clients = get_client_info();
$system_stats = get_system_stats();

// Подсчет статистики
$total_clients = count($clients);
$online_clients = 0;
$total_rx = 0;
$total_tx = 0;

if (!isset($wg_stats['error'])) {
    foreach ($wg_stats['peers'] as $peer) {
        if ($peer['status'] === 'Online') {
            $online_clients++;
        }

        // Конвертация трафика в байты для подсчета
        $rx_bytes = convert_to_bytes($peer['transfer_rx']);
        $tx_bytes = convert_to_bytes($peer['transfer_tx']);
        $total_rx += $rx_bytes;
        $total_tx += $tx_bytes;
    }
}

function convert_to_bytes($size_str) {
    if (preg_match('/(\d+(?:\.\d+)?)\s*([KMGT]iB|[KMGT]B)?/', $size_str, $matches)) {
        $size = floatval($matches[1]);
        $unit = $matches[2] ?? '';

        switch (strtoupper($unit)) {
            case 'KIB': case 'KB': return $size * 1024;
            case 'MIB': case 'MB': return $size * 1024 * 1024;
            case 'GIB': case 'GB': return $size * 1024 * 1024 * 1024;
            case 'TIB': case 'TB': return $size * 1024 * 1024 * 1024 * 1024;
            default: return $size;
        }
    }
    return 0;
}

function format_bytes($bytes) {
    if ($bytes >= 1024 * 1024 * 1024) {
        return number_format($bytes / (1024 * 1024 * 1024), 2) . ' GB';
    } elseif ($bytes >= 1024 * 1024) {
        return number_format($bytes / (1024 * 1024), 2) . ' MB';
    } elseif ($bytes >= 1024) {
        return number_format($bytes / 1024, 2) . ' KB';
    }
    return $bytes . ' B';
}
?>
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>WireGuard Obfuscation - Statistics</title>
    <meta http-equiv="refresh" content="<?php echo $refresh_interval; ?>">
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }

        .container {
            max-width: 1200px;
            margin: 0 auto;
        }

        .header {
            text-align: center;
            color: white;
            margin-bottom: 30px;
        }

        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }

        .header p {
            font-size: 1.1em;
            opacity: 0.9;
        }

        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }

        .card {
            background: rgba(255, 255, 255, 0.95);
            border-radius: 15px;
            padding: 25px;
            box-shadow: 0 8px 32px rgba(0,0,0,0.1);
            backdrop-filter: blur(10px);
        }

        .card h3 {
            color: #333;
            margin-bottom: 15px;
            font-size: 1.3em;
            border-bottom: 2px solid #667eea;
            padding-bottom: 10px;
        }

        .stat-item {
            display: flex;
            justify-content: space-between;
            margin-bottom: 10px;
            padding: 8px 0;
            border-bottom: 1px solid #eee;
        }

        .stat-item:last-child {
            border-bottom: none;
            margin-bottom: 0;
        }

        .stat-label {
            font-weight: 500;
            color: #555;
        }

        .stat-value {
            font-weight: bold;
            color: #333;
        }

        .status-online {
            color: #28a745;
        }

        .status-offline {
            color: #dc3545;
        }

        .peers-table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 15px;
        }

        .peers-table th,
        .peers-table td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #ddd;
        }

        .peers-table th {
            background-color: #f8f9fa;
            font-weight: 600;
            color: #495057;
        }

        .peers-table tr:hover {
            background-color: #f5f5f5;
        }

        .error {
            background: #f8d7da;
            color: #721c24;
            padding: 15px;
            border-radius: 8px;
            border: 1px solid #f5c6cb;
        }

        .footer {
            text-align: center;
            color: white;
            margin-top: 30px;
            opacity: 0.8;
        }

        @media (max-width: 768px) {
            .stats-grid {
                grid-template-columns: 1fr;
            }

            .peers-table {
                font-size: 0.9em;
            }

            .peers-table th,
            .peers-table td {
                padding: 8px 4px;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔒 WireGuard Obfuscation</h1>
            <p>Statistics Dashboard - <?php echo date('Y-m-d H:i:s'); ?></p>
        </div>

        <div class="stats-grid">
            <!-- Общая статистика -->
            <div class="card">
                <h3>📊 Общая статистика</h3>
                <div class="stat-item">
                    <span class="stat-label">Всего клиентов:</span>
                    <span class="stat-value"><?php echo $total_clients; ?></span>
                </div>
                <div class="stat-item">
                    <span class="stat-label">Онлайн:</span>
                    <span class="stat-value status-online"><?php echo $online_clients; ?></span>
                </div>
                <div class="stat-item">
                    <span class="stat-label">Офлайн:</span>
                    <span class="stat-value status-offline"><?php echo $total_clients - $online_clients; ?></span>
                </div>
                <div class="stat-item">
                    <span class="stat-label">Получено:</span>
                    <span class="stat-value"><?php echo format_bytes($total_rx); ?></span>
                </div>
                <div class="stat-item">
                    <span class="stat-label">Отправлено:</span>
                    <span class="stat-value"><?php echo format_bytes($total_tx); ?></span>
                </div>
            </div>

            <!-- Информация о сервере -->
            <div class="card">
                <h3>🖥️ Сервер</h3>
                <?php if (isset($wg_stats['error'])): ?>
                    <div class="error"><?php echo htmlspecialchars($wg_stats['error']); ?></div>
                <?php else: ?>
                    <div class="stat-item">
                        <span class="stat-label">Интерфейс:</span>
                        <span class="stat-value"><?php echo $wg_stats['server_info']['interface'] ?? 'Unknown'; ?></span>
                    </div>
                    <div class="stat-item">
                        <span class="stat-label">Порт:</span>
                        <span class="stat-value"><?php echo $wg_stats['server_info']['port'] ?? 'Unknown'; ?></span>
                    </div>
                    <div class="stat-item">
                        <span class="stat-label">Публичный ключ:</span>
                        <span class="stat-value" style="font-family: monospace; font-size: 0.8em;">
                            <?php echo substr($wg_stats['server_info']['public_key'] ?? 'Unknown', 0, 20) . '...'; ?>
                        </span>
                    </div>
                <?php endif; ?>
            </div>

            <!-- Системная информация -->
            <div class="card">
                <h3>⚙️ Система</h3>
                <div class="stat-item">
                    <span class="stat-label">Uptime:</span>
                    <span class="stat-value"><?php echo $system_stats['uptime'] ?? 'Unknown'; ?></span>
                </div>
                <div class="stat-item">
                    <span class="stat-label">Load Average:</span>
                    <span class="stat-value"><?php echo $system_stats['load_average'] ?? 'Unknown'; ?></span>
                </div>
                <div class="stat-item">
                    <span class="stat-label">RAM (всего):</span>
                    <span class="stat-value"><?php echo $system_stats['memory_total'] ?? 'Unknown'; ?></span>
                </div>
                <div class="stat-item">
                    <span class="stat-label">RAM (используется):</span>
                    <span class="stat-value"><?php echo $system_stats['memory_used'] ?? 'Unknown'; ?></span>
                </div>
            </div>
        </div>

        <!-- Таблица клиентов -->
        <div class="card">
            <h3>👥 Активные подключения</h3>
            <?php if (isset($wg_stats['error'])): ?>
                <div class="error">Не удается получить информацию о подключениях</div>
            <?php elseif (empty($wg_stats['peers'])): ?>
                <p>Нет активных подключений</p>
            <?php else: ?>
                <table class="peers-table">
                    <thead>
                        <tr>
                            <th>Клиент</th>
                            <th>IP адрес</th>
                            <th>Endpoint</th>
                            <th>Последний handshake</th>
                            <th>Трафик ↓/↑</th>
                            <th>Статус</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php foreach ($wg_stats['peers'] as $peer_key => $peer): ?>
                            <?php
                            // Ищем соответствующего клиента
                            $client_name = 'Unknown';
                            foreach ($clients as $name => $client) {
                                if ($client['public_key'] === $peer_key) {
                                    $client_name = $client['name'];
                                    break;
                                }
                            }
                            ?>
                            <tr>
                                <td><?php echo htmlspecialchars($client_name); ?></td>
                                <td style="font-family: monospace;"><?php echo htmlspecialchars($peer['allowed_ips']); ?></td>
                                <td style="font-family: monospace;"><?php echo htmlspecialchars($peer['endpoint']); ?></td>
                                <td><?php echo htmlspecialchars($peer['latest_handshake']); ?></td>
                                <td><?php echo htmlspecialchars($peer['transfer_rx'] . ' / ' . $peer['transfer_tx']); ?></td>
                                <td>
                                    <span class="<?php echo $peer['status'] === 'Online' ? 'status-online' : 'status-offline'; ?>">
                                        <?php echo $peer['status']; ?>
                                    </span>
                                </td>
                            </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            <?php endif; ?>
        </div>

        <div class="footer">
            <p>🔄 Обновляется автоматически каждые <?php echo $refresh_interval; ?> секунд</p>
            <p>WireGuard Obfuscation Setup v1.0</p>
        </div>
    </div>
</body>
</html>
