<?php
// Site de démonstration de la sandbox.
// Vérifie : docroot dynamique, PHP 8.5, connexion MySQL, envoi de mail (Mailpit).

header('Content-Type: text/html; charset=utf-8');

$checks = [];

// PHP
$checks['PHP'] = ['ok' => true, 'detail' => PHP_VERSION];

// Host / docroot dynamique
$checks['Docroot dynamique'] = [
    'ok' => true,
    'detail' => ($_SERVER['HTTP_HOST'] ?? '?') . ' → ' . ($_SERVER['DOCUMENT_ROOT'] ?? '?'),
];

// MySQL
try {
    $pdo = new PDO('mysql:host=mysql;dbname=sandbox', 'sandbox', 'sandbox', [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    ]);
    $version = $pdo->query('SELECT VERSION()')->fetchColumn();
    $checks['MySQL'] = ['ok' => true, 'detail' => 'connecté — ' . $version];
} catch (Throwable $e) {
    $checks['MySQL'] = ['ok' => false, 'detail' => $e->getMessage()];
}

// Mail -> Mailpit
$sent = mail(
    'test@docker.localhost',
    'Sandbox demo — ' . date('H:i:s'),
    'Ceci est un test envoyé depuis le site demo.',
    'From: noreply@docker.localhost'
);
$checks['Mail (Mailpit)'] = [
    'ok' => $sent,
    'detail' => $sent ? 'envoyé → voir mail.docker.localhost' : 'échec mail()',
];
?>
<!doctype html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Sandbox — demo</title>
    <!-- Assets Vite (dev). Nécessite le dev server lancé :
         docker compose exec apache sh -c 'cd sites/demo && npm run dev' -->
    <script type="module" src="http://vite.localhost/@vite/client"></script>
    <script type="module" src="http://vite.localhost/main.js"></script>
    <style>
        body { font-family: system-ui, sans-serif; max-width: 40rem; margin: 3rem auto; padding: 0 1rem; }
        h1 { font-size: 1.4rem; }
        ul { list-style: none; padding: 0; }
        li { padding: .6rem .8rem; border-radius: .5rem; margin: .4rem 0; background: #f4f4f5; }
        .ok::before { content: "✓ "; color: #16a34a; font-weight: bold; }
        .ko::before { content: "✗ "; color: #dc2626; font-weight: bold; }
        code { color: #6b7280; }
    </style>
</head>
<body>
    <h1>🧪 Sandbox — site <code><?= htmlspecialchars(explode('.', $_SERVER['HTTP_HOST'] ?? '')[0]) ?></code></h1>
    <p id="vite-app"><em>Vite non démarré (assets non chargés)</em></p>
    <ul>
        <?php foreach ($checks as $name => $c): ?>
            <li class="<?= $c['ok'] ? 'ok' : 'ko' ?>">
                <strong><?= htmlspecialchars($name) ?></strong> — <code><?= htmlspecialchars($c['detail']) ?></code>
            </li>
        <?php endforeach; ?>
    </ul>
</body>
</html>
