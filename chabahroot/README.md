# ChabahRoot — Production-Ready Kernel Telemetry Platform

**Version**: 1.0.0 | **Date**: May 12, 2026 | **Status**: Production Ready ✓

> Real-time kernel event telemetry platform combining eBPF kernel ingestion, event normalization, threat detection, and orchestration into a unified security monitoring solution.

---

## 📋 Overview

ChabahRoot is a 4-tier modular architecture designed for production security monitoring:

```
┌─────────────────────────────────────────────────────────────┐
│ M1: Kernel Ingestion (eBPF)                                 │
│ Author: MOUSAAB EL HARMALI                                  │
│ • Syscall tracing (execve, setuid, setgid, prctl)          │
│ • Ring buffer streaming                                     │
│ • <1ms latency, 1-2% CPU overhead                          │
└──────────────────┬──────────────────────────────────────────┘
                   │ Ring Buffer
                   ↓
┌─────────────────────────────────────────────────────────────┐
│ M3: Event Normalizer                                         │
│ Team: Équipe Cyber                                          │
│ • JSON schema normalization                                 │
│ • Context enrichment                                        │
│ • Sensitive data filtering                                  │
└──────────────────┬──────────────────────────────────────────┘
                   │ FIFO Pipe
                   ↓
┌─────────────────────────────────────────────────────────────┐
│ M2: Rules Engine                                            │
│ Team: Équipe Cyber                                          │
│ • 7 threat detection rules                                  │
│ • jq-based composable conditions                            │
│ • Extensible alert actions                                  │
└──────────────────┬──────────────────────────────────────────┘
                   │ Alerts
                   ↓
┌─────────────────────────────────────────────────────────────┐
│ M4: Pipeline Orchestrator                                   │
│ Team: Équipe Cyber                                          │
│ • Lifecycle management                                      │
│ • Health monitoring                                         │
│ • Integration test suite                                    │
└─────────────────────────────────────────────────────────────┘
```

---

## 🏗️ Architecture

### M1: Kernel Ingestion (kernel-ingestion/)

**Author**: MOUSAAB EL HARMALI

Entry point: `orchestrator.sh`

**Capabilities**:
- eBPF kernel probes on 4 syscalls
- Ring buffer streaming (256 KB, <1ms latency)
- System prerequisites validation
- eBPF program compilation and loading

**Key Files**:
- `orchestrator.sh` — M1 service orchestrator
- `integration.sh` — eBPF compilation and management
- `check.sh` — System prerequisites validation
- `init.sh` — Kernel layer initialization
- `cleanup.sh` — Resource cleanup
- `ebpf/event_capture.c` — eBPF kernel programs

---

### M2: Rules Engine (rules-engine/)

**Team**: Équipe Cyber

Entry point: `rules_engine.sh`

**Capabilities**:
- 7 production-ready threat detection rules
- jq-based composable conditions
- Alert generation with multiple severity levels
- Extensible action system (journal, slack, email)
- Offensive security audit mode
- Defensive continuous monitoring mode

**Key Files**:
- `rules_engine.sh` — Main detection engine
- `detection_rules.json` — 7 threat detection rules
- `offensive_audit.sh` — Security audit tool
- `defensive_monitor.sh` — Continuous monitoring

---

### M3: Event Normalizer (event-normalizer/)

**Team**: Équipe Cyber

Entry point: `ringbuf_reader.sh`

**Capabilities**:
- Continuous ring buffer reading
- Event decoding (hex → JSON)
- JSON schema normalization
- Parent process context enrichment
- Sensitive data filtering (password, token, secret, key)
- Event batch processing and caching

---

### M4: Pipeline Orchestrator (pipeline-orchestrator/)

**Team**: Équipe Cyber

Entry point: `orchestrator.sh`

**Capabilities**:
- Master pipeline orchestration
- Inter-service FIFO communication (M3 → M2)
- Process lifecycle management
- Health monitoring and auto-restart
- Comprehensive integration test suite
- Graceful shutdown handling

**Key Files**:
- `orchestrator.sh` — Master service orchestrator
- `integration_tests.sh` — Integration test suite
- `run_detection.sh` — Detection launcher

---

## 🔧 System Requirements

**Kernel**: Linux 4.0+ with eBPF support
- `CONFIG_BPF=y`
- `CONFIG_BPF_SYSCALL=y`

**Tools**:
- `bpftool` — eBPF program management
- `clang` — eBPF program compilation
- `llvm-strip` — Binary stripping
- `jq` — JSON query language

**Shell**: Bash 4.0+

**Privileges**: root (for M1 kernel operations)

---

## 🚀 Quick Start

### 1. Verify Prerequisites

```bash
sudo ./kernel-ingestion/check.sh
```

### 2. Start Pipeline

```bash
sudo ./pipeline-orchestrator/orchestrator.sh run
```

### 3. View Alerts (another terminal)

```bash
tail -f ./shared/logs/chabah.log
```

### 4. Check Status

```bash
sudo ./pipeline-orchestrator/orchestrator.sh status
```

### 5. Run Tests

```bash
sudo ./pipeline-orchestrator/orchestrator.sh test
```

---

## ⚙️ Configuration

**Centralized Configuration**: `shared/rules.conf`

```bash
# Log level: DEBUG, INFO, WARN, ALERT
LOG_LEVEL="INFO"

# Log file location
LOG_FILE="./shared/logs/chabah.log"

# Sensitive keywords to filter from logs
SENSITIVE_KEYWORDS="password token secret key"

# Polling interval (seconds)
POLL_INTERVAL="2"
```

**Detection Rules**: `rules-engine/detection_rules.json`

```json
{
  "id": "rule_exec_001",
  "name": "Binary execution from unsafe location",
  "type": "execution",
  "severity": "HIGH",
  "condition": ".event_type == \"exec\" and (.data.argv | test(\"^(/tmp|/dev/shm)\"))"
}
```

---

## 📊 Performance Characteristics

| Metric | Value |
|--------|-------|
| eBPF Latency | <1ms |
| CPU Overhead | 1-2% |
| Data Reduction | 10-100x |
| Ring Buffer | 256 KB |
| Detection Rules | 7 (extensible) |
| Polling Interval | 2s (configurable) |

---

## 📁 Directory Structure

```
chabahroot/
├── kernel-ingestion/               # M1 - eBPF Kernel Ingestion
│   ├── orchestrator.sh             Main service orchestrator
│   ├── integration.sh              eBPF compilation & loading
│   ├── check.sh                    Prerequisites validation
│   ├── init.sh                     Kernel layer init
│   ├── cleanup.sh                  Resource cleanup
│   ├── ebpf/
│   │   └── event_capture.c         eBPF kernel programs
│   └── lib/
│       └── lib_utils.sh            Shared utilities
│
├── rules-engine/                   # M2 - Threat Detection
│   ├── rules_engine.sh             Main rules engine
│   ├── detection_rules.json        7 detection rules
│   ├── offensive_audit.sh          Security audit
│   └── defensive_monitor.sh        Continuous monitoring
│
├── event-normalizer/               # M3 - Event Transport
│   └── ringbuf_reader.sh           Ring buffer reader
│
├── pipeline-orchestrator/          # M4 - Orchestration
│   ├── orchestrator.sh             Master orchestrator
│   └── integration_tests.sh        Test suite
│
└── shared/                         # Shared Resources
    ├── logger.sh                   Structured logging
    ├── rules.conf                  Unified config
    ├── logs/                       Log directory
    └── tmp/                        Temporary state
```

---

## 🔍 Detection Rules

The system includes 7 production-ready detection rules:

1. **rule_exec_001** — Binary execution from unsafe locations (/tmp, /dev/shm)
2. **rule_priv_001** — Privilege escalation via setuid(0)
3. **rule_priv_002** — Unauthorized processes running as root
4. **rule_susp_001** — Suspicious command patterns (curl, wget, ncat, etc.)
5. **rule_caps_001** — Capability modification by non-root users
6. **rule_cred_001** — Sensitive data in command arguments
7. **rule_suid_001** — SUID binary execution

All rules are JSON-based and support jq conditions for flexible customization.

---

## 🔐 Security

### Threat Detection

The Rules Engine monitors for:
- Privilege escalation attempts
- Suspicious command patterns
- Unauthorized root process execution
- Capability abuse
- Sensitive data exposure

### Data Protection

- Automatic filtering of sensitive keywords (password, token, secret, key)
- Parent process context enrichment for better investigation
- Centralized logging with access control

---

## 📈 Production Deployment

### Prerequisites Check

```bash
sudo ./kernel-ingestion/check.sh
```

### Full Pipeline Start

```bash
sudo ./pipeline-orchestrator/orchestrator.sh run
```

### Monitoring

```bash
# Real-time alerts
tail -f ./shared/logs/chabah.log

# Pipeline health
sudo ./pipeline-orchestrator/orchestrator.sh status

# Integration tests
sudo ./pipeline-orchestrator/orchestrator.sh test
```

### Configuration Customization

Edit `shared/rules.conf` for logging levels and keywords.  
Edit `rules-engine/detection_rules.json` to add/modify detection rules.

---

## 🤝 Team & Authorship

| Component | Responsibility | Team |
|-----------|-----------------|------|
| **Kernel Ingestion (M1)** | eBPF kernel telemetry | MOUSAAB EL HARMALI ⭐ |
| **Rules Engine (M2)** | Threat detection & analysis | Équipe Cyber |
| **Event Normalizer (M3)** | Transport & normalization | Équipe Cyber |
| **Pipeline Orchestrator (M4)** | Orchestration & testing | Équipe Cyber |

---

## 📄 License

**GPL v2** — Free and open-source software

---

## 🔗 Technical References

**eBPF**: Extended Berkeley Packet Filter — in-kernel bytecode execution  
**Ring Buffer**: BPF_MAP_TYPE_RINGBUF for kernel→userspace communication  
**Tracepoints**: Static kernel instrumentation points  
**jq**: JSON query language for composable rule conditions  
**Bash**: Shell automation and system integration

---

## 📞 Support

For issues or questions:
1. Review the `./kernel-ingestion/check.sh` prerequisites
2. Check `./shared/logs/chabah.log` for error messages
3. Run `./pipeline-orchestrator/orchestrator.sh test` for diagnostics

---

**Version**: 1.0.0 | **Last Updated**: 2026-05-12 | **Status**: Production Ready ✓

ChabahRoot — Real-time Kernel Telemetry Platform for Linux Security Monitoring
