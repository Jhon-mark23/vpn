<?php
header("Content-Type: application/json");

// Hardcoded API Token
$API_TOKEN = "admin";

// Script paths
$SCRIPTS = [
    'ssh' => '/usr/local/bin/ssh-api.sh',
    'vless' => '/usr/local/bin/vless-api.sh',
    'vmess' => '/usr/local/bin/vmess-api.sh'
];

// Check API Token
$token = $_GET['token'] ?? $_SERVER['HTTP_X_API_TOKEN'] ?? '';

if ($token !== $API_TOKEN) {
    http_response_code(403);
    echo json_encode([
        "success" => false,
        "message" => "Unauthorized - Invalid API Token"
    ]);
    exit;
}

// Get parameters
$type = $_GET['type'] ?? $_POST['type'] ?? '';
$username = $_GET['username'] ?? $_POST['username'] ?? '';
$password = $_GET['password'] ?? $_POST['password'] ?? '';
$duration = $_GET['duration'] ?? $_POST['duration'] ?? 30;

// Validate type
if (!isset($SCRIPTS[$type])) {
    echo json_encode([
        "success" => false,
        "message" => "Invalid type. Allowed: ssh, vless, vmess"
    ]);
    exit;
}

// Validate username
if (empty($username)) {
    echo json_encode([
        "success" => false,
        "message" => "Username is required"
    ]);
    exit;
}

// Build command based on type
$script = $SCRIPTS[$type];
$cmd = "bash " . escapeshellarg($script) . " " . escapeshellarg($username);

if ($type === 'ssh') {
    // SSH requires password
    if (empty($password)) {
        echo json_encode([
            "success" => false,
            "message" => "Password is required for SSH"
        ]);
        exit;
    }
    $cmd .= " " . escapeshellarg($password) . " " . escapeshellarg($duration);
} else {
    // VLESS and VMESS only need username and duration
    $cmd .= " " . escapeshellarg($duration);
}

$cmd .= " 2>&1";

// Execute
$output = shell_exec($cmd);

// Parse JSON output from bash script
$result = json_decode($output, true);

if ($result && isset($result['success'])) {
    echo json_encode($result, JSON_PRETTY_PRINT);
} else {
    echo json_encode([
        "success" => false,
        "message" => "Failed to create account",
        "type" => $type,
        "raw_output" => trim($output)
    ]);
}
?>