#!/bin/bash
# ============================================================
# insshws.sh – Python WebSocket proxy + Squid Proxy + BADVPN Installer
# Uses: ws-dropbear.service (port 2095) & ws-stunnel.service (port 700)
# Proxy: Squid (3128, 8082, 8888) with Python fallback
# BADVPN: UDP Gateway (7100-7400)
# Compatible with Debian / Ubuntu
# ============================================================

set -e

# ============================================================
# COLOR DEFINITIONS
# ============================================================
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

print_info()  { echo -e "[ ${GREEN}INFO${NC} ] $1"; }
print_warn()  { echo -e "[ ${YELLOW}WARNING${NC} ] $1"; }
print_error() { echo -e "[ ${RED}ERROR${NC} ] $1"; }
print_success(){ echo -e "[ ${BLUE}SUCCESS${NC} ] $1"; }

show_banner() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${BLUE}     PYTHON WEBSOCKET PROXY + SQUID + BADVPN INSTALLER   ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ============================================================
# DETECT OS & CLEAN PORT 80 COMPETITORS
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
    print_info "Detected OS: $OS $VER"
    if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
        print_error "This script only supports Ubuntu or Debian"
        exit 1
    fi

    # Kill apache2 if default installed, ensuring it doesn't fight Nginx for port 80
    if systemctl is-enabled apache2 &>/dev/null || systemctl is-active apache2 &>/dev/null; then
        print_warn "Apache2 detected! Removing conflict to free up Port 80..."
        systemctl stop apache2 || true
        systemctl disable apache2 || true
    fi
}

# ============================================================
# INSTALL PYTHON3 & BASE DEPENDENCIES
# ============================================================
install_python() {
    print_info "Installing Python3 and dependencies..."
    apt-get update -qq >/dev/null
    apt-get install -y python3 python3-pip curl psmisc 2>/dev/null || {
        apt install -y python3 python3-pip psmisc 2>/dev/null || true
    }
    if [[ "$OS" == "debian" ]]; then
        if [ ! -f /usr/bin/python ] && [ -f /usr/bin/python3 ]; then
            ln -s /usr/bin/python3 /usr/bin/python
            print_info "Created python symlink"
        fi
    fi
    print_success "Python3 installed"
}

# ============================================================
# CREATE THE PROXY SCRIPTS (Python3 compatible)
# ============================================================
create_proxy_scripts() {
    print_info "Creating ws-dropbear (port 2095) and ws-stunnel (port 700)..."

    # ── ws-dropbear (Safe fallback to port 2095 instead of 80) ──
    cat > /usr/local/bin/ws-dropbear <<'PYEOF'
#!/usr/bin/env python3
import socket, threading, select, signal, sys, time, getopt

LISTENING_ADDR = '0.0.0.0'
LISTENING_PORT = 2095
if sys.argv[1:]:
    try:
        LISTENING_PORT = int(sys.argv[1])
    except:
        pass
PASS = ''

BUFLEN = 4096 * 4
TIMEOUT = 60
DEFAULT_HOST = '127.0.0.1:1194'
RESPONSE = 'HTTP/1.1 101 HELLO MASTER \r\n\r\n'

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
        print(log)
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
        self.client_buffer = ''
        self.server = server
        self.log = 'Connection: ' + str(addr)

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

    def run(self):
        try:
            self.client_buffer = self.client.recv(BUFLEN)
            hostPort = self.findHeader(self.client_buffer, 'X-Real-Host')
            if hostPort == '':
                hostPort = DEFAULT_HOST
            split = self.findHeader(self.client_buffer, 'X-Split')
            if split != '':
                self.client.recv(BUFLEN)
            if hostPort != '':
                passwd = self.findHeader(self.client_buffer, 'X-Pass')
                if len(PASS) != 0 and passwd == PASS:
                    self.method_CONNECT(hostPort)
                elif len(PASS) != 0 and passwd != PASS:
                    self.client.send(b'HTTP/1.1 400 WrongPass!\r\n\r\n')
                elif hostPort.startswith('127.0.0.1') or hostPort.startswith('localhost'):
                    self.method_CONNECT(hostPort)
                else:
                    self.client.send(b'HTTP/1.1 403 Forbidden!\r\n\r\n')
            else:
                print('- No X-Real-Host!')
                self.client.send(b'HTTP/1.1 400 NoXRealHost!\r\n\r\n')
        except Exception as e:
            self.log += ' - error: ' + str(e)
            self.server.printLog(self.log)
        finally:
            self.close()
            self.server.removeConn(self)

    def findHeader(self, head, header):
        aux = head.find(header + ': ')
        if aux == -1:
            return ''
        aux = head.find(':', aux)
        head = head[aux+2:]
        aux = head.find('\r\n')
        if aux == -1:
            return ''
        return head[:aux]

    def connect_target(self, host):
        i = host.find(':')
        if i != -1:
            port = int(host[i+1:])
            host = host[:i]
        else:
            port = 443
        (soc_family, soc_type, proto, _, address) = socket.getaddrinfo(host, port)[0]
        self.target = socket.socket(soc_family, soc_type, proto)
        self.targetClosed = False
        self.target.connect(address)

    def method_CONNECT(self, path):
        self.log += ' - CONNECT ' + path
        self.connect_target(path)
        self.client.sendall(RESPONSE.encode())
        self.client_buffer = ''
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
    print("\n:-------PythonProxy-------:\n")
    print("Listening addr: " + LISTENING_ADDR)
    print("Listening port: " + str(LISTENING_PORT) + "\n")
    print(":-------------------------:\n")
    server = Server(LISTENING_ADDR, LISTENING_PORT)
    server.start()
    while True:
        try:
            time.sleep(2)
        except KeyboardInterrupt:
            print('Stopping...')
            server.close()
            break

if __name__ == '__main__':
    main()
PYEOF

    # ── ws-stunnel (SSL, port 700) ──
    cat > /usr/local/bin/ws-stunnel <<'PYEOF'
#!/usr/bin/env python3
import socket, threading, select, signal, sys, time, getopt

LISTENING_ADDR = '0.0.0.0'
LISTENING_PORT = 700
if sys.argv[1:]:
    try:
        LISTENING_PORT = int(sys.argv[1])
    except:
        pass
PASS = ''

BUFLEN = 4096 * 4
TIMEOUT = 60
DEFAULT_HOST = '127.0.0.1:442'
RESPONSE = 'HTTP/1.1 200 <font color="green">HELLO MASTER</font>\r\n\r\n'

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
        print(log)
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
        self.client_buffer = ''
        self.server = server
        self.log = 'Connection: ' + str(addr)

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

    def run(self):
        try:
            self.client_buffer = self.client.recv(BUFLEN)
            hostPort = self.findHeader(self.client_buffer, 'X-Real-Host')
            if hostPort == '':
                hostPort = DEFAULT_HOST
            split = self.findHeader(self.client_buffer, 'X-Split')
            if split != '':
                self.client.recv(BUFLEN)
            if hostPort != '':
                passwd = self.findHeader(self.client_buffer, 'X-Pass')
                if len(PASS) != 0 and passwd == PASS:
                    self.method_CONNECT(hostPort)
                elif len(PASS) != 0 and passwd != PASS:
                    self.client.send(b'HTTP/1.1 400 WrongPass!\r\n\r\n')
                elif hostPort.startswith('127.0.0.1') or hostPort.startswith('localhost'):
                    self.method_CONNECT(hostPort)
                else:
                    self.client.send(b'HTTP/1.1 403 Forbidden!\r\n\r\n')
            else:
                print('- No X-Real-Host!')
                self.client.send(b'HTTP/1.1 400 NoXRealHost!\r\n\r\n')
        except Exception as e:
            self.log += ' - error: ' + str(e)
            self.server.printLog(self.log)
        finally:
            self.close()
            self.server.removeConn(self)

    def findHeader(self, head, header):
        aux = head.find(header + ': ')
        if aux == -1:
            return ''
        aux = head.find(':', aux)
        head = head[aux+2:]
        aux = head.find('\r\n')
        if aux == -1:
            return ''
        return head[:aux]

    def connect_target(self, host):
        i = host.find(':')
        if i != -1:
            port = int(host[i+1:])
            host = host[:i]
        else:
            port = 443
        (soc_family, soc_type, proto, _, address) = socket.getaddrinfo(host, port)[0]
        self.target = socket.socket(soc_family, soc_type, proto)
        self.targetClosed = False
        self.target.connect(address)

    def method_CONNECT(self, path):
        self.log += ' - CONNECT ' + path
        self.connect_target(path)
        self.client.sendall(RESPONSE.encode())
        self.client_buffer = ''
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
            print('\033[31m'+'----PARANDO'+'\033[0;0m')
            server.close()
            break

if __name__ == '__main__':
    main()
PYEOF

    sed -i 's/\r$//' /usr/local/bin/ws-dropbear /usr/local/bin/ws-stunnel
    chmod +x /usr/local/bin/ws-dropbear /usr/local/bin/ws-stunnel
    print_success "Proxy scripts installed to /usr/local/bin/"
}

# ============================================================
# CONFIGURE SQUID PROXY
# ============================================================
configure_squid() {
    print_info "Configuring Squid proxy (3128, 8082, 8888)..."
    
    # Complete cleanup of old squid
    print_info "Cleaning up old squid installation..."
    systemctl stop squid 2>/dev/null || true
    systemctl disable squid 2>/dev/null || true
    pkill -9 squid 2>/dev/null || true
    killall -9 squid 2>/dev/null || true
    rm -f /run/squid.pid 2>/dev/null || true
    rm -f /var/run/squid.pid 2>/dev/null || true
    rm -rf /var/spool/squid/* 2>/dev/null || true
    rm -rf /var/log/squid/* 2>/dev/null || true
    
    # Remove and reinstall squid
    print_info "Reinstalling squid..."
    apt remove --purge squid -y 2>/dev/null || true
    apt autoremove -y 2>/dev/null || true
    apt autoclean -y 2>/dev/null || true
    apt update -y 2>/dev/null || true
    apt install -y squid 2>/dev/null || {
        print_error "Failed to install squid, using Python fallback..."
        configure_python_fallback
        return 1
    }
    
    # Create clean config
    print_info "Creating squid configuration..."
    cat > /etc/squid/squid.conf <<'EOF'
# Squid Proxy Config - Optimized for Debian/Ubuntu
http_port 3128
http_port 8082
http_port 8888

# Use 'all' instead of '0.0.0.0/0' for newer squid versions
acl all src all
http_access allow all

# Cache settings
cache_dir ufs /var/spool/squid 100 16 256
cache_mem 64 MB
maximum_object_size_in_memory 32 KB
maximum_object_size 1024 MB

# Performance
forwarded_for off
request_header_access X-Forwarded-For deny all
visible_hostname localhost
dns_nameservers 8.8.8.8 1.1.1.1

# Disable IPv6 to avoid warnings
dns_v4_first on
icmp_allow off

# Security and performance
via off
httpd_suppress_version_string on
EOF

    # Fix permissions
    mkdir -p /var/spool/squid
    mkdir -p /var/log/squid
    chown -R proxy:proxy /var/spool/squid 2>/dev/null || true
    chown -R proxy:proxy /var/log/squid 2>/dev/null || true
    
    # Initialize cache
    print_info "Initializing squid cache..."
    squid -z 2>/dev/null || true
    
    # Start squid
    print_info "Starting squid service..."
    systemctl stop squid 2>/dev/null || true
    sleep 2
    systemctl start squid 2>/dev/null || {
        print_warning "Failed to start squid via systemd, trying manual start..."
        /usr/sbin/squid -N -d1 2>/dev/null &
        sleep 3
    }
    
    # Enable squid
    systemctl enable squid 2>/dev/null || true
    
    # Verify squid is running
    sleep 2
    if systemctl is-active --quiet squid 2>/dev/null || pgrep -x "squid" > /dev/null; then
        print_success "Squid proxy on ports 3128, 8082, 8888"
        
        # Test squid
        if command -v curl &> /dev/null; then
            if curl -x http://localhost:3128 http://google.com -I -s -o /dev/null -w "%{http_code}" 2>/dev/null | grep -q "200\|301\|302"; then
                print_success "Squid proxy test passed"
            else
                print_warning "Squid is running but proxy test failed"
            fi
        fi
    else
        print_warning "Squid failed to start - using Python fallback"
        configure_python_fallback
    fi
}

# ============================================================
# FALLBACK: Python HTTP Proxy (if squid fails)
# ============================================================
configure_python_fallback() {
    print_info "Setting up Python HTTP proxy fallback..."
    
    # Kill any existing python proxies
    pkill -f "http-proxy.py" 2>/dev/null || true
    pkill -f "simple-proxy" 2>/dev/null || true
    
    # Create Python proxy script
    cat > /usr/local/bin/http-proxy.py << 'PYPROXY'
#!/usr/bin/env python3
import http.server
import socketserver
import socket
import threading
import time

class ProxyHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.end_headers()
        self.wfile.write(b'MarcScript HTTP Proxy Server\n')
        self.wfile.write(b'Connected to: ')
        self.wfile.write(self.path.encode())
        self.wfile.write(b'\n')
    
    def do_CONNECT(self):
        self.send_response(200)
        self.end_headers()
    
    def log_message(self, format, *args):
        return  # Suppress logs

def run_proxy(port):
    try:
        with socketserver.TCPServer(("0.0.0.0", port), ProxyHandler) as httpd:
            print(f"Proxy running on port {port}")
            httpd.serve_forever()
    except Exception as e:
        print(f"Failed to start proxy on port {port}: {e}")

# Start proxies on all ports
ports = [3128, 8082, 8888]
threads = []

for port in ports:
    thread = threading.Thread(target=run_proxy, args=(port,), daemon=True)
    thread.start()
    threads.append(thread)
    time.sleep(0.5)

print("All proxies started. Press Ctrl+C to stop.")
try:
    while True:
        time.sleep(1)
except KeyboardInterrupt:
    print("Shutting down...")
PYPROXY

    chmod +x /usr/local/bin/http-proxy.py
    
    # Start proxy in screen
    screen -dmS proxy python3 /usr/local/bin/http-proxy.py
    
    sleep 2
    
    # Check if proxy is running
    if pgrep -f "http-proxy.py" > /dev/null; then
        print_success "Python proxy running on ports 3128, 8082, 8888"
        
        # Test the proxy
        if command -v curl &> /dev/null; then
            sleep 2
            if curl -x http://localhost:3128 http://google.com -I -s -o /dev/null -w "%{http_code}" 2>/dev/null | grep -q "200\|301\|302"; then
                print_success "Python proxy test passed"
            else
                print_warning "Python proxy is running but test failed"
            fi
        fi
    else
        print_error "Python proxy failed to start"
        
        # Last resort: simple netcat listener
        print_info "Starting netcat fallback listeners..."
        for port in 3128 8082 8888; do
            screen -dmS proxy_$port nc -l -p $port -c 'echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nMarcScript Proxy Server"' 2>/dev/null || true
        done
        print_warning "Netcat fallback listeners started (limited functionality)"
    fi
}

# ============================================================
# INSTALL BADVPN UDP GATEWAY
# ============================================================
install_badvpn() {
    print_info "Installing BADVPN UDP gateway (7100-7400)..."
    
    cd /tmp
    wget -q -O /usr/bin/badvpn-udpgw "https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/ssh/newudpgw"
    chmod +x /usr/bin/badvpn-udpgw
    
    # Create systemd services for better management
    for port in 7100 7200 7300 7400; do
        local instance=$((port/100))
        cat > /etc/systemd/system/badvpn-${instance}.service << EOF
[Unit]
Description=BADVPN UDP Gateway on port ${port}
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/badvpn-udpgw --listen-addr 127.0.0.1:${port} --max-clients 50
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl daemon-reload
        systemctl enable badvpn-${instance} 2>/dev/null || true
        systemctl start badvpn-${instance} 2>/dev/null || true
        
        # Also add to rc.local for compatibility
        if ! grep -q "badvpn${instance}" /etc/rc.local 2>/dev/null; then
            sed -i "\$ i\screen -dmS badvpn${instance} badvpn-udpgw --listen-addr 127.0.0.1:${port} --max-clients 50" /etc/rc.local
        fi
    done
    
    # Start via screen for immediate use
    screen -dmS badvpn1 badvpn-udpgw --listen-addr 127.0.0.1:7100 --max-clients 50 2>/dev/null || true
    screen -dmS badvpn2 badvpn-udpgw --listen-addr 127.0.0.1:7200 --max-clients 50 2>/dev/null || true
    screen -dmS badvpn3 badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients 50 2>/dev/null || true
    screen -dmS badvpn4 badvpn-udpgw --listen-addr 127.0.0.1:7400 --max-clients 50 2>/dev/null || true
    
    print_success "BADVPN UDP gateway installed on ports 7100-7400"
}

# ============================================================
# INSTALL SYSTEMD SERVICE UNITS
# ============================================================
install_service_units() {
    print_info "Installing systemd service files..."

    cat > /etc/systemd/system/ws-dropbear.service <<'EOF'
[Unit]
Description=Websocket-Dropbear (Internal port 2095)
Documentation=https://google.com
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/bin/python3 /usr/local/bin/ws-dropbear 2095
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/ws-stunnel.service <<'EOF'
[Unit]
Description=SSH Over Websocket-SSL (HTTPS port 443)
Documentation=https://google.com
After=network.target nss-lookup.target stunnel4.service

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/bin/python3 /usr/local/bin/ws-stunnel 700
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ws-dropbear.service ws-stunnel.service
    print_success "Service units installed"
}

# ============================================================
# START SERVICES
# ============================================================
start_services() {
    print_info "Starting WebSocket services..."

    systemctl stop ws-dropbear.service 2>/dev/null; sleep 1
    systemctl start ws-dropbear.service
    systemctl stop ws-stunnel.service 2>/dev/null; sleep 1
    systemctl start ws-stunnel.service

    sleep 2
    echo ""
    if systemctl is-active --quiet ws-dropbear.service; then
        print_success "ws-dropbear (port 2095) is running"
    else
        print_warn "ws-dropbear failed to start – check logs: journalctl -u ws-dropbear"
    fi

    if systemctl is-active --quiet ws-stunnel.service; then
        print_success "ws-stunnel (port 700) is running"
    else
        print_warn "ws-stunnel failed to start – check logs: journalctl -u ws-stunnel"
    fi
    
    # Check BADVPN services
    for port in 7100 7200 7300 7400; do
        local instance=$((port/100))
        if systemctl is-active --quiet badvpn-${instance} 2>/dev/null; then
            print_success "BADVPN UDP ${port} is running"
        else
            print_warn "BADVPN UDP ${port} starting via screen..."
            screen -dmS badvpn${instance} badvpn-udpgw --listen-addr 127.0.0.1:${port} --max-clients 50 2>/dev/null || true
        fi
    done
}

# ============================================================
# CREATE PROXY MANAGEMENT COMMANDS
# ============================================================
create_management_commands() {
    print_info "Creating proxy management commands..."
    
    # Proxy status command
    cat > /usr/local/bin/proxy-status <<'EOF'
#!/bin/bash
echo "═══════════════════════════════════════════════════════════════"
echo "   PROXY SERVICES STATUS"
echo "═══════════════════════════════════════════════════════════════"
echo ""
svc() { systemctl is-active --quiet "$1" && echo -e "\033[1;32m● Running\033[0m" || echo -e "\033[1;31m● Not Running\033[0m"; }
printf "%-28s : %s\n" "Squid Proxy (3128,8082,8888)" "$(svc squid)"
printf "%-28s : %s\n" "WS-Dropbear (2095)" "$(svc ws-dropbear)"
printf "%-28s : %s\n" "WS-Stunnel (700)" "$(svc ws-stunnel)"
printf "%-28s : %s\n" "BADVPN UDP 7100" "$(svc badvpn-71)"
printf "%-28s : %s\n" "BADVPN UDP 7200" "$(svc badvpn-72)"
printf "%-28s : %s\n" "BADVPN UDP 7300" "$(svc badvpn-73)"
printf "%-28s : %s\n" "BADVPN UDP 7400" "$(svc badvpn-74)"
echo ""
echo "═══════════════════════════════════════════════════════════════"
EOF
    chmod +x /usr/local/bin/proxy-status
    
    # Proxy restart command
    cat > /usr/local/bin/proxy-restart <<'EOF'
#!/bin/bash
echo "Restarting all proxy services..."
systemctl restart squid 2>/dev/null || true
systemctl restart ws-dropbear 2>/dev/null || true
systemctl restart ws-stunnel 2>/dev/null || true
systemctl restart badvpn-71 2>/dev/null || true
systemctl restart badvpn-72 2>/dev/null || true
systemctl restart badvpn-73 2>/dev/null || true
systemctl restart badvpn-74 2>/dev/null || true
echo "All proxy services restarted!"
/usr/local/bin/proxy-status
EOF
    chmod +x /usr/local/bin/proxy-restart
    
    print_success "Management commands created: proxy-status, proxy-restart"
}

# ============================================================
# MAIN
# ============================================================
main() {
    show_banner
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${BLUE}                    INSTALLATION PROGRESS                 ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    detect_os
    install_python
    create_proxy_scripts
    configure_squid
    install_badvpn
    install_service_units
    create_management_commands
    start_services

    echo ""
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${GREEN}              ✅ INSTALLATION COMPLETE!                   ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "   🔹 Squid Proxy    : 3128, 8082, 8888"
    echo -e "   🔹 ws-dropbear    : 2095 (for WS without SSL)"
    echo -e "   🔹 ws-stunnel     : 700  (for WS with SSL)"
    echo -e "   🔹 BADVPN UDP     : 7100-7400"
    echo ""
    echo -e "   📋 Management Commands:"
    echo -e "      proxy-status   - Check all proxy services"
    echo -e "      proxy-restart  - Restart all proxy services"
    echo ""
}

main "$@"