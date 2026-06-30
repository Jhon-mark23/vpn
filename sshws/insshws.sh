#!/bin/bash
# ============================================================
# MARCSCRIPT SSH WEBSOCKET + PYTHON PROXY INSTALLER
# Uses custom Python proxies (socks.py & socks-ssh.py)
# Compatible with Debian & Ubuntu
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

# ============================================================
# BANNER
# ============================================================
show_banner() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${NC}                                                          ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${NC}     ██╗  ██╗██████╗ ██╗    ██╗███████╗██╗  ██╗${PURPLE}║${NC}"
    echo -e "${PURPLE}║${NC}     ██║  ██║██╔══██╗██║    ██║██╔════╝██║  ██║${PURPLE}║${NC}"
    echo -e "${PURPLE}║${NC}     ███████║██████╔╝██║ █╗ ██║███████╗███████║${PURPLE}║${NC}"
    echo -e "${PURPLE}║${NC}     ██╔══██║██╔═══╝ ██║███╗██║╚════██║██╔══██║${PURPLE}║${NC}"
    echo -e "${PURPLE}║${NC}     ██║  ██║██║     ╚███╔███╔╝███████║██║  ██║${PURPLE}║${NC}"
    echo -e "${PURPLE}║${NC}     ╚═╝  ╚═╝╚═╝      ╚══╝╚══╝ ╚══════╝╚═╝  ╚═╝${PURPLE}║${NC}"
    echo -e "${PURPLE}║${NC}                                                          ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${BLUE}           PYTHON WEBSOCKET PROXY INSTALLER              ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${NC}                                                          ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ============================================================
# DETECT OS
# ============================================================
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        print_error "Cannot detect OS"
        exit 1
    fi
    print_info "Detected OS: $OS"
    
    if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
        print_error "This script only supports Ubuntu or Debian"
        exit 1
    fi
}

# ============================================================
# INSTALL PYTHON AND DEPENDENCIES
# ============================================================
install_python() {
    print_info "Installing Python and dependencies..."
    
    apt-get install -y python3 python3-pip python3-venv 2>/dev/null || {
        print_warn "Python3 installation failed, trying apt..."
        apt install -y python3 python3-pip 2>/dev/null || true
    }
    
    # Create python symlink for Debian
    if [[ "$OS" == "debian" ]]; then
        if [ ! -f /usr/bin/python ] && [ -f /usr/bin/python3 ]; then
            ln -s /usr/bin/python3 /usr/bin/python
            print_info "Created python symlink for Debian"
        fi
    fi
    
    # Install Python packages
    pip3 install --upgrade pip 2>/dev/null || true
    pip3 install websocket-client 2>/dev/null || true
    
    print_success "Python installed"
}

# ============================================================
# INSTALL PYTHON PROXY SCRIPTS
# ============================================================
install_proxy_scripts() {
    print_info "Installing Python proxy scripts..."
    
    # Create directory
    mkdir -p /opt/sshws-proxy
    
    # Copy socks.py to /opt/sshws-proxy/
    cat > /opt/sshws-proxy/socks.py <<'EOF'
import socket, threading, thread, select, signal, sys, time, getopt

# Listen
LISTENING_ADDR = '0.0.0.0'
if sys.argv[1:]:
  LISTENING_PORT = sys.argv[1]
else:
  LISTENING_PORT = 80  
#Pass
PASS = ''

# CONST
BUFLEN = 4096 * 4
TIMEOUT = 60
DEFAULT_HOST = '127.0.0.1:1194'
RESPONSE = 'HTTP/1.1 101 Dexter Eskalarte \r\n\r\n'
#RESPONSE = 'HTTP/1.1 200 Hello_World!\r\nContent-length: 0\r\n\r\nHTTP/1.1 200 Connection established\r\n\r\n'  # lint:ok

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
        intport = int(self.port)
        self.soc.bind((self.host, intport))
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
        print log
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
                    self.client.send('HTTP/1.1 400 WrongPass!\r\n\r\n')
                elif hostPort.startswith('127.0.0.1') or hostPort.startswith('localhost'):
                    self.method_CONNECT(hostPort)
                else:
                    self.client.send('HTTP/1.1 403 Forbidden!\r\n\r\n')
            else:
                print '- No X-Real-Host!'
                self.client.send('HTTP/1.1 400 NoXRealHost!\r\n\r\n')

        except Exception as e:
            self.log += ' - error: ' + e.strerror
            self.server.printLog(self.log)
	    pass
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

        return head[:aux];

    def connect_target(self, host):
        i = host.find(':')
        if i != -1:
            port = int(host[i+1:])
            host = host[:i]
        else:
            if self.method=='CONNECT':
                port = 443
            else:
                port = sys.argv[1]

        (soc_family, soc_type, proto, _, address) = socket.getaddrinfo(host, port)[0]

        self.target = socket.socket(soc_family, soc_type, proto)
        self.targetClosed = False
        self.target.connect(address)

    def method_CONNECT(self, path):
        self.log += ' - CONNECT ' + path

        self.connect_target(path)
        self.client.sendall(RESPONSE)
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


def print_usage():
    print 'Usage: proxy.py -p <port>'
    print '       proxy.py -b <bindAddr> -p <port>'
    print '       proxy.py -b 0.0.0.0 -p 80'

def parse_args(argv):
    global LISTENING_ADDR
    global LISTENING_PORT
    
    try:
        opts, args = getopt.getopt(argv,"hb:p:",["bind=","port="])
    except getopt.GetoptError:
        print_usage()
        sys.exit(2)
    for opt, arg in opts:
        if opt == '-h':
            print_usage()
            sys.exit()
        elif opt in ("-b", "--bind"):
            LISTENING_ADDR = arg
        elif opt in ("-p", "--port"):
            LISTENING_PORT = int(arg)


def main(host=LISTENING_ADDR, port=LISTENING_PORT):
    print "\n:-------PythonProxy-------:\n"
    print "Listening addr: " + LISTENING_ADDR
    print "Listening port: " + str(LISTENING_PORT) + "\n"
    print ":-------------------------:\n"
    server = Server(LISTENING_ADDR, LISTENING_PORT)
    server.start()
    while True:
        try:
            time.sleep(2)
        except KeyboardInterrupt:
            print 'Stopping...'
            server.close()
            break

#######    parse_args(sys.argv[1:])
if __name__ == '__main__':
    main()
EOF

    # Copy socks-ssh.py to /opt/sshws-proxy/
    cat > /opt/sshws-proxy/socks-ssh.py <<'EOF'
#!/usr/bin/env python3
# encoding: utf-8

import socket, threading, thread, select, signal, sys, time, getopt

# Python Proxy ou Socks

# Porta do Proxy
proxyport = 8000

# CONFIG
LISTENING_ADDR = '0.0.0.0'
LISTENING_PORT = proxyport

PASS = ''

# CONST
BUFLEN = 4096 * 4
TIMEOUT = 60
DEFAULT_HOST = '127.0.0.1:442'
RESPONSE = 'HTTP/1.1 200 <font color="green">Dexter Eskalarte</font>\r\n\r\n'
#RESPONSE = 'HTTP/1.1 200 Hello_World!\r\nContent-length: 0\r\n\r\nHTTP/1.1 200 Connection established\r\n\r\n'  # lint:ok


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
        print log
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
                    self.client.send('HTTP/1.1 400 WrongPass!\r\n\r\n')
                elif hostPort.startswith('127.0.0.1') or hostPort.startswith('localhost'):
                    self.method_CONNECT(hostPort)
                else:
                    self.client.send('HTTP/1.1 403 Forbidden!\r\n\r\n')
            else:
                print '- No X-Real-Host!'
                self.client.send('HTTP/1.1 400 NoXRealHost!\r\n\r\n')

        except Exception as e:
            self.log += ' - error: ' + e.strerror
            self.server.printLog(self.log)
	    pass
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

        return head[:aux];

    def connect_target(self, host):
        i = host.find(':')
        if i != -1:
            port = int(host[i+1:])
            host = host[:i]
        else:
            if self.method=='CONNECT':
                port = 443
            else:
                port = 80

        (soc_family, soc_type, proto, _, address) = socket.getaddrinfo(host, port)[0]

        self.target = socket.socket(soc_family, soc_type, proto)
        self.targetClosed = False
        self.target.connect(address)

    def method_CONNECT(self, path):
        self.log += ' - CONNECT ' + path

        self.connect_target(path)
        self.client.sendall(RESPONSE)
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


def print_usage():
    print 'Usage: proxy.py -p <port>'
    print '       proxy.py -b <bindAddr> -p <port>'
    print '       proxy.py -b 0.0.0.0 -p 80'

def parse_args(argv):
    global LISTENING_ADDR
    global LISTENING_PORT

    try:
        opts, args = getopt.getopt(argv,"hb:p:",["bind=","port="])
    except getopt.GetoptError:
        print_usage()
        sys.exit(2)
    for opt, arg in opts:
        if opt == '-h':
            print_usage()
            sys.exit()
        elif opt in ("-b", "--bind"):
            LISTENING_ADDR = arg
        elif opt in ("-p", "--port"):
            LISTENING_PORT = int(arg)


def main(host=LISTENING_ADDR, port=LISTENING_PORT):
    server = Server(LISTENING_ADDR, LISTENING_PORT)
    server.start()

    while True:
        try:
            time.sleep(2)
        except KeyboardInterrupt:
            print '\033[31m'+'----PARANDO'+'\033[0;0m'
            server.close()
            break

if __name__ == '__main__':
    parse_args(sys.argv[1:])
    main()
EOF

    # Make scripts executable
    chmod +x /opt/sshws-proxy/socks.py
    chmod +x /opt/sshws-proxy/socks-ssh.py
    
    print_success "Python proxy scripts installed to /opt/sshws-proxy/"
}

# ============================================================
# CREATE SYSTEMD SERVICES
# ============================================================
create_services() {
    print_info "Creating systemd services..."

    # Service for socks.py (port 80 - SSH WebSocket)
    cat > /etc/systemd/system/ws-proxy.service <<'EOF'
[Unit]
Description=SSH WebSocket Proxy (socks.py)
Documentation=https://github.com/XTLS/Xray-install
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/sshws-proxy
ExecStart=/usr/bin/python3 /opt/sshws-proxy/socks.py 2095
Restart=always
RestartSec=3
LimitNOFILE=65536
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # Service for socks-ssh.py (port 700 - SSH WebSocket SSL)
    cat > /etc/systemd/system/ws-stunnel.service <<'EOF'
[Unit]
Description=SSH WebSocket SSL Proxy (socks-ssh.py)
Documentation=https://github.com/XTLS/Xray-install
After=network.target nss-lookup.target stunnel4.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/sshws-proxy
ExecStart=/usr/bin/python3 /opt/sshws-proxy/socks-ssh.py 700
Restart=always
RestartSec=3
LimitNOFILE=65536
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ws-proxy.service
    systemctl enable ws-stunnel.service

    # Start services
    systemctl stop ws-proxy.service 2>/dev/null; sleep 1
    systemctl start ws-proxy.service
    systemctl stop ws-stunnel.service 2>/dev/null; sleep 1
    systemctl start ws-stunnel.service

    # Verify services
    echo ""
    print_info "Checking WebSocket services..."

    if systemctl is-active --quiet ws-proxy.service; then
        print_success "ws-proxy (port 2095) running"
    else
        print_warn "ws-proxy failed to start - checking logs..."
        journalctl -u ws-proxy.service -n 5 --no-pager
    fi

    if systemctl is-active --quiet ws-stunnel.service; then
        print_success "ws-stunnel (port 700) running"
    else
        print_warn "ws-stunnel failed to start - checking logs..."
        journalctl -u ws-stunnel.service -n 5 --no-pager
    fi
}

# ============================================================
# CREATE MANAGEMENT SCRIPT
# ============================================================
create_management_script() {
    cat > /usr/local/bin/wsproxy <<'EOF'
#!/bin/bash
case "$1" in
    start|stop|restart|status)
        systemctl $1 ws-proxy
        systemctl $1 ws-stunnel
        ;;
    start-ws)
        systemctl start ws-proxy
        ;;
    stop-ws)
        systemctl stop ws-proxy
        ;;
    start-wss)
        systemctl start ws-stunnel
        ;;
    stop-wss)
        systemctl stop ws-stunnel
        ;;
    logs)
        journalctl -u ws-proxy -f
        ;;
    logs-wss)
        journalctl -u ws-stunnel -f
        ;;
    kill)
        fuser -k 2095/tcp 2>/dev/null
        fuser -k 700/tcp 2>/dev/null
        echo "WebSocket ports (2095, 700) killed"
        ;;
    *)
        echo "Usage: wsproxy {start|stop|restart|status|logs|kill|start-ws|stop-ws|start-wss|stop-wss|logs-wss}"
        echo ""
        echo "  start     - Start both WebSocket services"
        echo "  stop      - Stop both WebSocket services"
        echo "  restart   - Restart both WebSocket services"
        echo "  status    - Check both WebSocket services"
        echo "  logs      - View ws-proxy logs"
        echo "  logs-wss  - View ws-stunnel logs"
        echo "  kill      - Kill WebSocket ports"
        echo "  start-ws  - Start ws-proxy only"
        echo "  stop-ws   - Stop ws-proxy only"
        echo "  start-wss - Start ws-stunnel only"
        echo "  stop-wss  - Stop ws-stunnel only"
        ;;
esac
EOF
    chmod +x /usr/local/bin/wsproxy
    print_success "Management script created (wsproxy)"
}

# ============================================================
# CREATE CONNECTION GUIDE
# ============================================================
create_guide() {
    VPS_IP=$(curl -s ifconfig.me || curl -s ipv4.icanhazip.com || echo "unknown")
    
    cat > /root/ssh-ws-proxy-guide.txt <<EOF
===========================================
   SSH WEBSOCKET + PYTHON PROXY GUIDE
   (socks.py & socks-ssh.py)
===========================================

VPS IP: $VPS_IP

===========================================
1. SSH OVER WEBSOCKET (socks.py)
===========================================
   Port: 2095
   ssh -o ProxyCommand="websocat ws://$VPS_IP:2095" root@$VPS_IP

===========================================
2. SSH OVER WEBSOCKET + SSL (socks-ssh.py)
===========================================
   Port: 700
   ssh -o ProxyCommand="websocat wss://$VPS_IP:700" root@$VPS_IP

===========================================
3. HTTP INJECTOR / KPN TUNNEL SETTINGS
===========================================
   SSH Host: $VPS_IP
   SSH Port: 2095 (WS) or 700 (WSS)
   
   For Payload with Proxy:
   SSH Host: $VPS_IP
   SSH Port: 22 (or 2222)
   Proxy: HTTP
   Proxy Host: $VPS_IP
   Proxy Port: 3128

===========================================
MANAGEMENT
===========================================
   wsproxy     - Manage WebSocket services
   vpn-status  - Check all services
===========================================
EOF

    print_success "Connection guide saved to /root/ssh-ws-proxy-guide.txt"
}

# ============================================================
# UPDATE VPN-STATUS
# ============================================================
update_vpn_status() {
    if [ -f /usr/local/bin/vpn-status ]; then
        cat > /usr/local/bin/vpn-status <<'EOF'
#!/bin/bash
echo "═══════════════════════════════════════════════════════════════"
echo "   SSH VPN + WEBSOCKET PROXY STATUS"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "SSH Server      : $(systemctl is-active ssh)   (22, 9696)"
echo "Dropbear        : $(systemctl is-active dropbear)   (109, 143)"
echo "Stunnel4        : $(systemctl is-active stunnel4)   (222, 777)"
echo "ws-proxy        : $(systemctl is-active ws-proxy)   (2095) [socks.py]"
echo "ws-stunnel      : $(systemctl is-active ws-stunnel)   (700) [socks-ssh.py]"
echo "Nginx           : $(systemctl is-active nginx)   (80, 443, 81)"
echo "Fail2ban        : $(systemctl is-active fail2ban)"
echo "BADVPN          : $(pgrep -c badvpn-udpgw || echo 0) instances (7100-7400)"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  VPS IP: $(curl -s ifconfig.me || echo 'unknown')"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Commands:"
echo "  menu         - Original menu"
echo "  create       - Create SSH user"
echo "  wsproxy      - Manage WebSocket services"
echo "  vpn-status   - Show this status"
echo "═══════════════════════════════════════════════════════════════"
EOF
        chmod +x /usr/local/bin/vpn-status
        print_success "vpn-status updated"
    fi
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
    
    echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${NC}"
    echo -e "${GREEN}│  Installing Python WebSocket Proxy (socks.py)          │${NC}"
    echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${NC}"
    
    detect_os
    install_python
    install_proxy_scripts
    create_services
    create_management_script
    create_guide
    update_vpn_status
    
    echo ""
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${GREEN}              ✅ INSTALLATION COMPLETE!                   ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}                   📡 WEBSOCKET SERVICES${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${GREEN}   ws-proxy     :${NC} ${YELLOW}2095${NC} (socks.py - SSH over WS)"
    echo -e "${GREEN}   ws-stunnel   :${NC} ${YELLOW}700${NC}  (socks-ssh.py - SSH over WSS)"
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}                   🔧 MANAGEMENT${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "   ${GREEN}wsproxy${NC}     - Manage WebSocket services"
    echo -e "   ${GREEN}vpn-status${NC}  - Check all services"
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${WHITE}           THANK YOU FOR USING MARCSCRIPT!              ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    print_success "Python WebSocket proxy installation completed!"
}

# ============================================================
# RUN MAIN
# ============================================================
main "$@"