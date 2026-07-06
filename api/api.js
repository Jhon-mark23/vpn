const http = require('http');
const url = require('url');
const { exec } = require('child_process');

// Hardcoded API Token
const API_TOKEN = 'admin';

// Script paths (same as before)
const SCRIPTS = {
    ssh: '/usr/local/bin/ssh-api.sh',
    vless: '/usr/local/bin/vless-api.sh',
    vmess: '/usr/local/bin/vmess-api.sh'
};

// Allowed types
const ALLOWED_TYPES = Object.keys(SCRIPTS);

// Helper to parse JSON body
function parseBody(req) {
    return new Promise((resolve, reject) => {
        let body = '';
        req.on('data', chunk => { body += chunk; });
        req.on('end', () => {
            try {
                if (body) {
                    const parsed = JSON.parse(body);
                    resolve(parsed);
                } else {
                    resolve({});
                }
            } catch (err) {
                reject(err);
            }
        });
        req.on('error', reject);
    });
}

// Helper to send JSON response
function sendJSON(res, status, data) {
    res.writeHead(status, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(data, null, 2));
}

// Create HTTP server
const server = http.createServer(async (req, res) => {
    // Only handle /api.php (or /api.js) – we keep the same endpoint for compatibility
    const parsedUrl = url.parse(req.url, true);
    const pathname = parsedUrl.pathname;

    // Accept both /api.php and /api.js (and /)
    if (!pathname.endsWith('/api.php') && !pathname.endsWith('/api.js') && pathname !== '/') {
        sendJSON(res, 404, { success: false, message: 'Not found' });
        return;
    }

    // Get method and parameters
    const method = req.method;

    // Extract query parameters (GET)
    let query = parsedUrl.query;

    // For POST, we need to read body
    let bodyParams = {};
    if (method === 'POST') {
        try {
            bodyParams = await parseBody(req);
        } catch (err) {
            sendJSON(res, 400, { success: false, message: 'Invalid JSON body' });
            return;
        }
    }

    // Merge parameters (GET takes precedence, but we'll combine: query overrides body)
    const params = { ...bodyParams, ...query };

    // Check token (first from query, then from header, then body)
    const token = params.token || req.headers['x-api-token'] || '';
    if (token !== API_TOKEN) {
        sendJSON(res, 403, { success: false, message: 'Unauthorized - Invalid API Token' });
        return;
    }

    // Extract parameters
    const type = params.type || '';
    const username = params.username || '';
    const password = params.password || '';
    const duration = parseInt(params.duration, 10) || 30;

    // Validate type
    if (!ALLOWED_TYPES.includes(type)) {
        sendJSON(res, 400, {
            success: false,
            message: 'Invalid type. Allowed: ' + ALLOWED_TYPES.join(', ')
        });
        return;
    }

    // Validate username
    if (!username || username.trim() === '') {
        sendJSON(res, 400, { success: false, message: 'Username is required' });
        return;
    }

    // Build command
    const script = SCRIPTS[type];
    let cmd = `bash ${escapeShellArg(script)} ${escapeShellArg(username)}`;

    if (type === 'ssh') {
        if (!password || password.trim() === '') {
            sendJSON(res, 400, { success: false, message: 'Password is required for SSH' });
            return;
        }
        cmd += ` ${escapeShellArg(password)} ${escapeShellArg(duration)}`;
    } else {
        // VLESS and VMESS only need username and duration
        cmd += ` ${escapeShellArg(duration)}`;
    }

    cmd += ' 2>&1';

    // Execute command
    exec(cmd, (error, stdout, stderr) => {
        // stdout contains JSON from bash script (or error messages)
        const output = stdout || stderr || '';
        let result;
        try {
            result = JSON.parse(output);
        } catch (e) {
            // Not JSON – treat as error
            sendJSON(res, 500, {
                success: false,
                message: 'Failed to create account',
                type: type,
                raw_output: output.trim()
            });
            return;
        }

        // If result is valid JSON and contains success
        if (result && typeof result === 'object' && 'success' in result) {
            sendJSON(res, 200, result);
        } else {
            sendJSON(res, 500, {
                success: false,
                message: 'Unexpected output',
                type: type,
                raw_output: output.trim()
            });
        }
    });
});

// Simple shell argument escaping (equivalent to escapeshellarg)
function escapeShellArg(arg) {
    if (typeof arg !== 'string') arg = String(arg);
    // Replace single quotes with '\'' and wrap in single quotes
    return "'" + arg.replace(/'/g, "'\\''") + "'";
}

// Start server
const PORT = process.env.API_PORT || 1123;
server.listen(PORT, '0.0.0.0', () => {
    console.log(`API server listening on port ${PORT}`);
});

// Graceful shutdown
process.on('SIGINT', () => {
    console.log('Shutting down...');
    server.close(() => process.exit(0));
});