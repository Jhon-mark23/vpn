#!/bin/bash
# ============================================================
# MARCSCRIPT PYTHON WEBSOCKET PROXY INSTALLER
# (Python-based WebSocket Proxy for SSH Tunneling)
# 
# Ports:
#   8080 - SSH WebSocket (Direct) - Python
#   8445 - SSH WebSocket SSL (via Stunnel) - Python
#   9443 - SSH WebSocket SSL (Python WS + SSL)
#   9445 - SSH WebSocket (Python WS Direct)
#
# Author: MarcScript
# Version: 2.0 (Python WS Only - No Dropbear/Stunnel WS)
# ============================================================


export DEBIAN_FRONTEND=noninteractive

# ---------- COLOURS ----------
red='\e[1;31m'
green='\e[0;32m'
yell='\e[1;33m'
blue='\e[0;34m'
purple='\e[1;35m'
cyan='\e[1;36m'
NC='\e[0m'

print_info()  { echo -e "[ ${green}INFO${NC} ] $1"; }
print_error() { echo -e "[ ${red}ERROR${NC} ] $1"; }
print_warning(){ echo -e "[ ${yell}WARN${NC} ] $1"; }
print_success(){ echo -e "[ ${cyan}OK${NC} ] $1"; }

# ============================================================
# DETECT OS
# ============================================================
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        print_error "Cannot detect OS"
        exit 1
    fi
    
    case "$OS" in
        ubuntu|debian)
            print_info "Detected OS: $OS $VER"
            ;;
        *)
            print_error "This script only supports Ubuntu or Debian"
            exit 1
            ;;
    esac
}

# ============================================================
# INSTALL PYTHON3
# ============================================================
install_python() {
    print_info "Checking Python3 installation..."
    
    if command -v python3 &>/dev/null; then
        PYTHON_VERSION=$(python3 --version)
        print_info "Python3 already installed: $PYTHON_VERSION"
    else
        print_info "Installing Python3..."
        apt update -y 2>/dev/null
        apt install -y python3 python3-pip 2>/dev/null || {
            print_error "Failed to install Python3"
            return 1
        }
    fi
    
    # Ensure python symlink exists
    if [ ! -f /usr/bin/python ]; then
        ln -s /usr/bin/python3 /usr/bin/python 2>/dev/null || true
    fi
    
    print_success "Python3 ready: $(python3 --version)"
    return 0
}

# ============================================================
# CREATE WS DIRECTORY
# ============================================================
setup_ws_directory() {
    print_info "Setting up Python WS proxy directory..."
    mkdir -p /opt/ws-proxy
    mkdir -p /var/log/ws-proxy
    
    # Clean old logs
    rm -f /var/log/ws-proxy/*.log 2>/dev/null || true
}

# ============================================================
# WS PROXY 1: SSH WS PORT 8080 (Direct Python WebSocket)
# ============================================================
create_ws_8080() {
    print_info "Creating Python WS Proxy on Port 8080 (SSH Direct)..."
    
    cat > /opt/ws-proxy/ws-8080.py <<'PYEOF'
#!/usr/bin/env python3
# ============================================================
# MARCSCRIPT PYTHON WS PROXY - PORT 8080
# SSH WebSocket Direct
# ============================================================
import socket, threading, select, sys, time

LISTENING_ADDR = '0.0.0.0'
LISTENING_PORT = 8080
BUFLEN = 4096 * 4
TIMEOUT = 60
DEFAULT_HOST = '127.0.0.1:22'
RESPONSE = 'HTTP/1.1 101 <font color="green">MARCSCRIPT</font>\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nServer: MarcScript-WS\r\n\r\n'

class Server(threading.Thread):
    def __init__(self, host, port):
        threading.Thread.__init__(self)
        self.running = False
        self.host = host
        self.port = port
        self.threads = []
        self.threadsLock = threading.Lock()
        self.logLock = threading.Lock()

    def run(self):
        self.soc = socket.socket(socket.AF_INET)
        self.soc.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.soc.settimeout(2)
        self.soc.bind((self.host, self.port))
        self.soc.listen(0)
        self.running = True
        self.printLog(f'[STARTED] WS Proxy on port {self.port} -> {DEFAULT_HOST}')

        try:
            while self.running:
                try:
                    c, addr = self.soc.accept()
                    c.setblocking(1)
                except socket.timeout:
                    continue
                conn = ConnectionHandler(c, self, addr)
                conn.start()
                self.addConn(conn)
        finally:
            self.running = False
            self.soc.close()

    def printLog(self, log):
        self.logLock.acquire()
        ts = time.strftime('%Y-%m-%d %H:%M:%S')
        print(f'[{ts}] {log}')
        self.logLock.release()

    def addConn(self, conn):
        try:
            self.threadsLock.acquire()
            if self.running:
                self.threads.append(conn)
        finally:
            self.threadsLock.release()

    def removeConn(self, conn):
        try:
            self.threadsLock.acquire()
            self.threads.remove(conn)
        finally:
            self.threadsLock.release()

    def close(self):
        try:
            self.running = False
            self.threadsLock.acquire()
            threads = list(self.threads)
            for c in threads:
                c.close()
        finally:
            self.threadsLock.release()

class ConnectionHandler(threading.Thread):
    def __init__(self, socClient, server, addr):
        threading.Thread.__init__(self)
        self.clientClosed = False
        self.targetClosed = True
        self.client = socClient
        self.client_buffer = b''
        self.server = server
        self.log = f'Connection: {addr[0]}:{addr[1]}'

    def close(self):
        try:
            if not self.clientClosed:
                self.client.shutdown(socket.SHUT_RDWR)
                self.client.close()
        except:
            pass
        finally:
            self.clientClosed = True
        try:
            if not self.targetClosed:
                self.target.shutdown(socket.SHUT_RDWR)
                self.target.close()
        except:
            pass
        finally:
            self.targetClosed = True

    def findHeader(self, head, header):
        head_str = head.decode('utf-8', errors='ignore')
        search = header + ': '
        aux = head_str.find(search)
        if aux == -1:
            return ''
        aux = head_str.find(':', aux)
        head_str = head_str[aux+2:]
        aux = head_str.find('\r\n')
        if aux == -1:
            return ''
        return head_str[:aux]

    def run(self):
        try:
            self.client_buffer = self.client.recv(BUFLEN)
            hostPort = self.findHeader(self.client_buffer, 'X-Real-Host')
            if hostPort == '':
                hostPort = DEFAULT_HOST
            
            if hostPort != '':
                if hostPort.startswith('127.0.0.1') or hostPort.startswith('localhost'):
                    self.method_CONNECT(hostPort)
                else:
                    # Allow connection to configured backend
                    self.method_CONNECT(hostPort)
            else:
                self.log += ' - No X-Real-Host'
                self.client.send(b'HTTP/1.1 400 NoXRealHost\r\n\r\n')
        except Exception as e:
            self.log += f' - error: {str(e)}'
            self.server.printLog(self.log)
        finally:
            self.close()
            self.server.removeConn(self)

    def connect_target(self, host):
        i = host.find(':')
        if i != -1:
            port = int(host[i+1:])
            host = host[:i]
        else:
            port = 22
        (soc_family, soc_type, proto, _, address) = socket.getaddrinfo(host, port)[0]
        self.target = socket.socket(soc_family, soc_type, proto)
        self.targetClosed = False
        self.target.connect(address)

    def method_CONNECT(self, path):
        self.log += f' - CONNECT {path}'
        self.connect_target(path)
        self.client.sendall(RESPONSE.encode())
        self.client_buffer = b''
        self.server.printLog(self.log)
        self.doCONNECT()

    def doCONNECT(self):
        socs = [self.client, self.target]
        count = 0
        error = False
        while True:
            count += 1
            (recv, _, err) = select.select(socs, [], socs, 3)
            if err:
                error = True
            if recv:
                for in_ in recv:
                    try:
                        data = in_.recv(BUFLEN)
                        if data:
                            if in_ is self.target:
                                self.client.send(data)
                            else:
                                while data:
                                    byte = self.target.send(data)
                                    data = data[byte:]
                            count = 0
                        else:
                            break
                    except:
                        error = True
                        break
            if count == TIMEOUT:
                error = True
            if error:
                break

def main():
    server = Server(LISTENING_ADDR, LISTENING_PORT)
    server.start()
    while True:
        try:
            time.sleep(2)
        except KeyboardInterrupt:
            print('Stopping WS Proxy 8080...')
            server.close()
            break

if __name__ == '__main__':
    main()
PYEOF

    chmod +x /opt/ws-proxy/ws-8080.py
    print_success "WS Proxy 8080 script created"
}

# ============================================================
# WS PROXY 2: SSH WS PORT 9445 (Python WebSocket Direct)
# ============================================================
create_ws_9445() {
    print_info "Creating Python WS Proxy on Port 9445 (SSH WS Direct)..."
    
    cat > /opt/ws-proxy/ws-9445.py <<'PYEOF'
#!/usr/bin/env python3
# ============================================================
# MARCSCRIPT PYTHON WS PROXY - PORT 9445
# SSH WebSocket Direct (Alternative)
# ============================================================
import socket, threading, select, sys, time

LISTENING_ADDR = '0.0.0.0'
LISTENING_PORT = 9445
BUFLEN = 4096 * 4
TIMEOUT = 60
DEFAULT_HOST = '127.0.0.1:22'
RESPONSE = 'HTTP/1.1 101 <font color="green">MARCSCRIPT</font>\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nServer: MarcScript-WS\r\n\r\n'

class Server(threading.Thread):
    def __init__(self, host, port):
        threading.Thread.__init__(self)
        self.running = False
        self.host = host
        self.port = port
        self.threads = []
        self.threadsLock = threading.Lock()
        self.logLock = threading.Lock()

    def run(self):
        self.soc = socket.socket(socket.AF_INET)
        self.soc.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.soc.settimeout(2)
        self.soc.bind((self.host, self.port))
        self.soc.listen(0)
        self.running = True
        self.printLog(f'[STARTED] WS Proxy on port {self.port} -> {DEFAULT_HOST}')

        try:
            while self.running:
                try:
                    c, addr = self.soc.accept()
                    c.setblocking(1)
                except socket.timeout:
                    continue
                conn = ConnectionHandler(c, self, addr)
                conn.start()
                self.addConn(conn)
        finally:
            self.running = False
            self.soc.close()

    def printLog(self, log):
        self.logLock.acquire()
        ts = time.strftime('%Y-%m-%d %H:%M:%S')
        print(f'[{ts}] {log}')
        self.logLock.release()

    def addConn(self, conn):
        try:
            self.threadsLock.acquire()
            if self.running:
                self.threads.append(conn)
        finally:
            self.threadsLock.release()

    def removeConn(self, conn):
        try:
            self.threadsLock.acquire()
            self.threads.remove(conn)
        finally:
            self.threadsLock.release()

    def close(self):
        try:
            self.running = False
            self.threadsLock.acquire()
            threads = list(self.threads)
            for c in threads:
                c.close()
        finally:
            self.threadsLock.release()

class ConnectionHandler(threading.Thread):
    def __init__(self, socClient, server, addr):
        threading.Thread.__init__(self)
        self.clientClosed = False
        self.targetClosed = True
        self.client = socClient
        self.client_buffer = b''
        self.server = server
        self.log = f'Connection: {addr[0]}:{addr[1]}'

    def close(self):
        try:
            if not self.clientClosed:
                self.client.shutdown(socket.SHUT_RDWR)
                self.client.close()
        except:
            pass
        finally:
            self.clientClosed = True
        try:
            if not self.targetClosed:
                self.target.shutdown(socket.SHUT_RDWR)
                self.target.close()
        except:
            pass
        finally:
            self.targetClosed = True

    def findHeader(self, head, header):
        head_str = head.decode('utf-8', errors='ignore')
        search = header + ': '
        aux = head_str.find(search)
        if aux == -1:
            return ''
        aux = head_str.find(':', aux)
        head_str = head_str[aux+2:]
        aux = head_str.find('\r\n')
        if aux == -1:
            return ''
        return head_str[:aux]

    def run(self):
        try:
            self.client_buffer = self.client.recv(BUFLEN)
            hostPort = self.findHeader(self.client_buffer, 'X-Real-Host')
            if hostPort == '':
                hostPort = DEFAULT_HOST
            
            if hostPort != '':
                if hostPort.startswith('127.0.0.1') or hostPort.startswith('localhost'):
                    self.method_CONNECT(hostPort)
                else:
                    self.method_CONNECT(hostPort)
            else:
                self.log += ' - No X-Real-Host'
                self.client.send(b'HTTP/1.1 400 NoXRealHost\r\n\r\n')
        except Exception as e:
            self.log += f' - error: {str(e)}'
            self.server.printLog(self.log)
        finally:
            self.close()
            self.server.removeConn(self)

    def connect_target(self, host):
        i = host.find(':')
        if i != -1:
            port = int(host[i+1:])
            host = host[:i]
        else:
            port = 22
        (soc_family, soc_type, proto, _, address) = socket.getaddrinfo(host, port)[0]
        self.target = socket.socket(soc_family, soc_type, proto)
        self.targetClosed = False
        self.target.connect(address)

    def method_CONNECT(self, path):
        self.log += f' - CONNECT {path}'
        self.connect_target(path)
        self.client.sendall(RESPONSE.encode())
        self.client_buffer = b''
        self.server.printLog(self.log)
        self.doCONNECT()

    def doCONNECT(self):
        socs = [self.client, self.target]
        count = 0
        error = False
        while True:
            count += 1
            (recv, _, err) = select.select(socs, [], socs, 3)
            if err:
                error = True
            if recv:
                for in_ in recv:
                    try:
                        data = in_.recv(BUFLEN)
                        if data:
                            if in_ is self.target:
                                self.client.send(data)
                            else:
                                while data:
                                    byte = self.target.send(data)
                                    data = data[byte:]
                            count = 0
                        else:
                            break
                    except:
                        error = True
                        break
            if count == TIMEOUT:
                error = True
            if error:
                break

def main():
    server = Server(LISTENING_ADDR, LISTENING_PORT)
    server.start()
    while True:
        try:
            time.sleep(2)
        except KeyboardInterrupt:
            print('Stopping WS Proxy 9445...')
            server.close()
            break

if __name__ == '__main__':
    main()
PYEOF

    chmod +x /opt/ws-proxy/ws-9445.py
    print_success "WS Proxy 9445 script created"
}

# ============================================================
# WS PROXY 3: SSH WS SSL PORT 9443 (Python WS + SSL)
# ============================================================
create_ws_9443() {
    print_info "Creating Python WS SSL Proxy on Port 9443 (SSH WS + SSL)..."
    
    cat > /opt/ws-proxy/ws-9443.py <<'PYEOF'
#!/usr/bin/env python3
# ============================================================
# MARCSCRIPT PYTHON WS SSL PROXY - PORT 9443
# SSH WebSocket + SSL (Direct SSL/TLS)
# ============================================================
import socket, threading, select, ssl, sys, time, os

LISTENING_ADDR = '0.0.0.0'
LISTENING_PORT = 9443
BUFLEN = 4096 * 4
TIMEOUT = 60
DEFAULT_HOST = '127.0.0.1:22'
RESPONSE = 'HTTP/1.1 101 <font color="green">MARCSCRIPT</font>\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nServer: MarcScript-WSS\r\n\r\n'

# SSL Certificate paths
CERT_FILE = '/etc/stunnel/stunnel.pem'
KEY_FILE = '/etc/stunnel/stunnel.pem'

class Server(threading.Thread):
    def __init__(self, host, port):
        threading.Thread.__init__(self)
        self.running = False
        self.host = host
        self.port = port
        self.threads = []
        self.threadsLock = threading.Lock()
        self.logLock = threading.Lock()
        self.ssl_context = None

    def setup_ssl(self):
        """Setup SSL context"""
        if os.path.exists(CERT_FILE):
            self.ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            self.ssl_context.load_cert_chain(CERT_FILE, KEY_FILE)
            self.ssl_context.check_hostname = False
            self.ssl_context.verify_mode = ssl.CERT_NONE
            # Allow legacy ciphers for compatibility
            self.ssl_context.set_ciphers('DEFAULT:!aNULL:!eNULL:!LOW:!MD5:!EXP:!RC4')
            self.printLog(f'[SSL] Using certificate: {CERT_FILE}')
            return True
        else:
            self.printLog(f'[WARN] Certificate not found: {CERT_FILE}')
            # Generate self-signed cert as fallback
            self.printLog('[SSL] Generating self-signed certificate...')
            os.makedirs('/etc/stunnel', exist_ok=True)
            os.system(f'openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
                -keyout {CERT_FILE} -out {CERT_FILE} \
                -subj "/C=PH/ST=Manila/L=Manila/O=MarcScript/CN=VPS" 2>/dev/null')
            if os.path.exists(CERT_FILE):
                self.ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
                self.ssl_context.load_cert_chain(CERT_FILE, KEY_FILE)
                self.ssl_context.check_hostname = False
                self.ssl_context.verify_mode = ssl.CERT_NONE
                self.ssl_context.set_ciphers('DEFAULT:!aNULL:!eNULL:!LOW:!MD5:!EXP:!RC4')
                return True
        return False

    def run(self):
        self.soc = socket.socket(socket.AF_INET)
        self.soc.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.soc.settimeout(2)
        self.soc.bind((self.host, self.port))
        self.soc.listen(0)
        self.running = True
        
        # Setup SSL
        ssl_ok = self.setup_ssl()
        if ssl_ok:
            self.printLog(f'[STARTED] WSS Proxy on port {self.port} -> {DEFAULT_HOST}')
        else:
            self.printLog(f'[STARTED] WS Proxy on port {self.port} -> {DEFAULT_HOST} (NO SSL)')

        try:
            while self.running:
                try:
                    c, addr = self.soc.accept()
                    c.setblocking(1)
                    
                    # Wrap with SSL if available
                    if self.ssl_context:
                        try:
                            c = self.ssl_context.wrap_socket(c, server_side=True)
                        except ssl.SSLError as e:
                            self.printLog(f'SSL Error from {addr}: {e}')
                            c.close()
                            continue
                except socket.timeout:
                    continue
                
                conn = ConnectionHandler(c, self, addr)
                conn.start()
                self.addConn(conn)
        finally:
            self.running = False
            self.soc.close()

    def printLog(self, log):
        self.logLock.acquire()
        ts = time.strftime('%Y-%m-%d %H:%M:%S')
        print(f'[{ts}] {log}')
        self.logLock.release()

    def addConn(self, conn):
        try:
            self.threadsLock.acquire()
            if self.running:
                self.threads.append(conn)
        finally:
            self.threadsLock.release()

    def removeConn(self, conn):
        try:
            self.threadsLock.acquire()
            self.threads.remove(conn)
        finally:
            self.threadsLock.release()

    def close(self):
        try:
            self.running = False
            self.threadsLock.acquire()
            threads = list(self.threads)
            for c in threads:
                c.close()
        finally:
            self.threadsLock.release()

class ConnectionHandler(threading.Thread):
    def __init__(self, socClient, server, addr):
        threading.Thread.__init__(self)
        self.clientClosed = False
        self.targetClosed = True
        self.client = socClient
        self.client_buffer = b''
        self.server = server
        self.log = f'Connection: {addr[0]}:{addr[1]}'

    def close(self):
        try:
            if not self.clientClosed:
                self.client.shutdown(socket.SHUT_RDWR)
                self.client.close()
        except:
            pass
        finally:
            self.clientClosed = True
        try:
            if not self.targetClosed:
                self.target.shutdown(socket.SHUT_RDWR)
                self.target.close()
        except:
            pass
        finally:
            self.targetClosed = True

    def findHeader(self, head, header):
        head_str = head.decode('utf-8', errors='ignore')
        search = header + ': '
        aux = head_str.find(search)
        if aux == -1:
            return ''
        aux = head_str.find(':', aux)
        head_str = head_str[aux+2:]
        aux = head_str.find('\r\n')
        if aux == -1:
            return ''
        return head_str[:aux]

    def run(self):
        try:
            self.client_buffer = self.client.recv(BUFLEN)
            hostPort = self.findHeader(self.client_buffer, 'X-Real-Host')
            if hostPort == '':
                hostPort = DEFAULT_HOST
            
            if hostPort != '':
                if hostPort.startswith('127.0.0.1') or hostPort.startswith('localhost'):
                    self.method_CONNECT(hostPort)
                else:
                    self.method_CONNECT(hostPort)
            else:
                self.log += ' - No X-Real-Host'
                self.client.send(b'HTTP/1.1 400 NoXRealHost\r\n\r\n')
        except Exception as e:
            self.log += f' - error: {str(e)}'
            self.server.printLog(self.log)
        finally:
            self.close()
            self.server.removeConn(self)

    def connect_target(self, host):
        i = host.find(':')
        if i != -1:
            port = int(host[i+1:])
            host = host[:i]
        else:
            port = 22
        (soc_family, soc_type, proto, _, address) = socket.getaddrinfo(host, port)[0]
        self.target = socket.socket(soc_family, soc_type, proto)
        self.targetClosed = False
        self.target.connect(address)

    def method_CONNECT(self, path):
        self.log += f' - CONNECT {path}'
        self.connect_target(path)
        self.client.sendall(RESPONSE.encode())
        self.client_buffer = b''
        self.server.printLog(self.log)
        self.doCONNECT()

    def doCONNECT(self):
        socs = [self.client, self.target]
        count = 0
        error = False
        while True:
            count += 1
            (recv, _, err) = select.select(socs, [], socs, 3)
            if err:
                error = True
            if recv:
                for in_ in recv:
                    try:
                        data = in_.recv(BUFLEN)
                        if data:
                            if in_ is self.target:
                                self.client.send(data)
                            else:
                                while data:
                                    byte = self.target.send(data)
                                    data = data[byte:]
                            count = 0
                        else:
                            break
                    except:
                        error = True
                        break
            if count == TIMEOUT:
                error = True
            if error:
                break

def main():
    server = Server(LISTENING_ADDR, LISTENING_PORT)
    server.start()
    while True:
        try:
            time.sleep(2)
        except KeyboardInterrupt:
            print('Stopping WSS Proxy 9443...')
            server.close()
            break

if __name__ == '__main__':
    main()
PYEOF

    chmod +x /opt/ws-proxy/ws-9443.py
    print_success "WSS Proxy 9443 script created"
}

# ============================================================
# CREATE SYSTEMD SERVICES
# ============================================================
create_systemd_services() {
    print_info "Creating systemd services for Python WS proxies..."

    # WS Proxy 8080 (SSH Direct)
    cat > /etc/systemd/system/ws-8080.service <<'EOF'
[Unit]
Description=Python WS Proxy Port 8080 (SSH Direct)
After=network.target ssh.service
Wants=ssh.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/ws-proxy/ws-8080.py
Restart=always
RestartSec=5
User=root
WorkingDirectory=/opt/ws-proxy
StandardOutput=append:/var/log/ws-proxy/ws-8080.log
StandardError=append:/var/log/ws-proxy/ws-8080.log
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    # WS Proxy 9445 (SSH WS Direct)
    cat > /etc/systemd/system/ws-9445.service <<'EOF'
[Unit]
Description=Python WS Proxy Port 9445 (SSH WS Direct)
After=network.target ssh.service
Wants=ssh.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/ws-proxy/ws-9445.py
Restart=always
RestartSec=5
User=root
WorkingDirectory=/opt/ws-proxy
StandardOutput=append:/var/log/ws-proxy/ws-9445.log
StandardError=append:/var/log/ws-proxy/ws-9445.log
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    # WSS Proxy 9443 (SSH WS + SSL)
    cat > /etc/systemd/system/ws-9443.service <<'EOF'
[Unit]
Description=Python WSS Proxy Port 9443 (SSH WS + SSL)
After=network.target ssh.service
Wants=ssh.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/ws-proxy/ws-9443.py
Restart=always
RestartSec=5
User=root
WorkingDirectory=/opt/ws-proxy
StandardOutput=append:/var/log/ws-proxy/ws-9443.log
StandardError=append:/var/log/ws-proxy/ws-9443.log
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    print_success "Systemd services created"
}

# ============================================================
# START SERVICES
# ============================================================
start_services() {
    print_info "Starting Python WS proxy services..."
    
    systemctl daemon-reload
    
    local services=("ws-8080" "ws-9445" "ws-9443")
    
    for svc in "${services[@]}"; do
        print_info "Starting $svc..."
        systemctl stop "$svc" 2>/dev/null
        sleep 1
        systemctl enable "$svc" 2>/dev/null || true
        systemctl start "$svc" 2>/dev/null
    done
    
    sleep 3
}

# ============================================================
# VERIFY SERVICES
# ============================================================
verify_services() {
    print_info "Verifying Python WS proxy services..."
    echo ""
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${purple}   PYTHON WS PROXY SERVICE STATUS${NC}"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    check_service() {
        local name="$1"
        local port="$2"
        local desc="$3"
        if systemctl is-active --quiet "$name"; then
            echo -e " ${green}●${NC} $name (Port $port) - ${desc} ${green}Running${NC}"
            return 0
        else
            echo -e " ${red}●${NC} $name (Port $port) - ${desc} ${red}Not Running${NC}"
            return 1
        fi
    }
    
    check_service "ws-8080" "8080" "SSH Direct"
    check_service "ws-9445" "9445" "SSH WS Direct"
    check_service "ws-9443" "9443" "SSH WS + SSL"
    
    echo ""
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# ============================================================
# CREATE LOG ROTATION
# ============================================================
setup_logrotate() {
    print_info "Setting up log rotation..."
    
    cat > /etc/logrotate.d/ws-proxy <<'EOF'
/var/log/ws-proxy/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 0640 root root
    sharedscripts
    postrotate
        systemctl restart ws-8080 ws-9445 ws-9443 > /dev/null 2>&1 || true
    endscript
}
EOF
    
    print_success "Log rotation configured"
}

# ============================================================
# MAIN
# ============================================================
main() {
    clear
    echo -e "${cyan}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${cyan}║${purple}     PYTHON WEBSOCKET PROXY INSTALLER                    ${cyan}║${NC}"
    echo -e "${cyan}║${purple}     SSH WS Direct + SSH WS SSL Support                  ${cyan}║${NC}"
    echo -e "${cyan}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${green}Ports:${NC}"
    echo -e "  ${cyan}8080${NC} - SSH WebSocket (Python WS Direct)"
    echo -e "  ${cyan}8445${NC} - SSH WebSocket SSL (via Stunnel)"
    echo -e "  ${cyan}9443${NC} - SSH WebSocket SSL (Python WSS + SSL)"
    echo -e "  ${cyan}9445${NC} - SSH WebSocket (Python WS Direct Alt)"
    echo ""
    
    # Check root
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root"
        exit 1
    fi
    
    detect_os
    
    # Install Python3
    if ! install_python; then
        print_error "Failed to install Python3. Exiting."
        exit 1
    fi
    
    # Setup directories
    setup_ws_directory
    
    # Create proxy scripts
    create_ws_8080
    create_ws_9445
    create_ws_9443
    
    # Create systemd services
    create_systemd_services
    
    # Setup log rotation
    setup_logrotate
    
    # Start services
    start_services
    
    # Verify
    verify_services
    
    # Cleanup
    rm -f /root/insshws.sh 2>/dev/null
    
    echo ""
    print_success "Python WebSocket Proxy installation complete!"
    echo ""
    echo -e "${cyan}Quick Commands:${NC}"
    echo "  systemctl status ws-8080        - Check WS 8080"
    echo "  systemctl status ws-9445        - Check WS 9445"
    echo "  systemctl status ws-9443        - Check WSS 9443"
    echo "  systemctl restart ws-8080       - Restart WS 8080"
    echo "  journalctl -u ws-8080 -f        - View WS 8080 logs"
    echo ""
    echo -e "${cyan}Protocol Summary:${NC}"
    echo "  SSH Direct WS    : ws://IP:8080  (Payload: GET / HTTP/1.1[crlf]Upgrade: websocket[crlf][crlf])"
    echo "  SSH WS Alt       : ws://IP:9445  (Payload: GET / HTTP/1.1[crlf]Upgrade: websocket[crlf][crlf])"
    echo "  SSH WSS SSL      : wss://IP:9443 (Payload: GET / HTTP/1.1[crlf]Upgrade: websocket[crlf][crlf])"
    echo "  SSH SSL (Stunnel): ssl://IP:8443,8444,8445"
    echo ""
}

main "$@"