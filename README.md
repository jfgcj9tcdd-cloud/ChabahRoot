# ChabahRoot — Plateforme de Télémétrie Noyau en Temps Réel

**Version**: 1.0.0 | **Date**: May 12, 2026 | **Status**: Production Ready ✓

> **ChabahRoot** est une plateforme complète de détection des menaces basée sur la télémétrie système temps réel. Utilisant eBPF pour l'ingestion kernel (<1ms latency, 1-2% CPU), elle fournit une détection de menaces par un moteur de règles JSON.

---

## 🎯 Architecture Production-Ready

Le projet est organisé en **4 services autonomes** avec une communication structurée via FIFO pipes:

```
┌──────────────────────────────────────────────────────────┐
│ M1: Kernel Ingestion (MOUSAAB EL HARMALI)               │
│ • eBPF Probes: execve, setuid, setgid, prctl            │
│ • Ring Buffer streaming (256 KB)                        │
│ • <1ms latency, 1-2% CPU, 10-100x data reduction       │
└──────────────┬───────────────────────────────────────────┘
               │ Ring Buffer (kernel→userspace)
               ↓
┌──────────────────────────────────────────────────────────┐
│ M3: Event Normalizer (Équipe Cyber)                     │
│ • Ring buffer reader & JSON normalization               │
│ • Parent process enrichment                             │
│ • Sensitive data filtering                              │
└──────────────┬───────────────────────────────────────────┘
               │ FIFO Pipe (event_stream.pipe)
               ↓
┌──────────────────────────────────────────────────────────┐
│ M2: Rules Engine (Équipe Cyber)                         │
│ • 7 production-ready detection rules                     │
│ • jq-based composable conditions                         │
│ • Actions: journal, slack, email (extensible)          │
└──────────────┬───────────────────────────────────────────┘
               │ Alerts & Logs
               ↓
┌──────────────────────────────────────────────────────────┐
│ M4: Pipeline Orchestrator (Équipe Cyber)                │
│ • Lifecycle management & health monitoring              │
│ • Auto-restart on failure                               │
│ • Integration test suite & validation                   │
└──────────────────────────────────────────────────────────┘
```

---

## 📦 Services

### **M1: Kernel Ingestion**
**Location**: `chabahroot/kernel-ingestion/` | **Author**: MOUSAAB EL HARMALI
- ✓ eBPF kernel probes (4 tracepoints)
- ✓ Ring buffer streaming
- ✓ System prerequisites validation
- ✓ Event capture with <1ms latency

### **M2: Rules Engine**
**Location**: `chabahroot/rules-engine/` | **Author**: Équipe Cyber
- ✓ 7 detection rules (JSON-based)
- ✓ Threat pattern matching
- ✓ Offensive audit & defensive monitoring
- ✓ Extensible alert actions

### **M3: Event Normalizer**
**Location**: `chabahroot/event-normalizer/` | **Author**: Équipe Cyber
- ✓ Ring buffer reader
- ✓ Event normalization to JSON
- ✓ Process context enrichment
- ✓ Sensitive data filtering

### **M4: Pipeline Orchestrator**
**Location**: `chabahroot/pipeline-orchestrator/` | **Author**: Équipe Cyber
- ✓ Master pipeline orchestration
- ✓ Inter-service communication (FIFO)
- ✓ Process lifecycle management
- ✓ Integration test suite

---

## 📁 Directory Structure

```
chabahroot/
├── kernel-ingestion/               # M1 Service
│   ├── orchestrator.sh
│   ├── integration.sh
│   ├── check.sh
│   ├── init.sh
│   ├── cleanup.sh
│   ├── ebpf/
│   │   └── event_capture.c
│   └── lib/
│       └── lib_utils.sh
├── rules-engine/                   # M2 Service
│   ├── rules_engine.sh
│   ├── detection_rules.json
│   ├── offensive_audit.sh
│   └── defensive_monitor.sh
├── event-normalizer/               # M3 Service
│   └── ringbuf_reader.sh
├── pipeline-orchestrator/          # M4 Service
│   ├── orchestrator.sh
│   ├── integration_tests.sh
│   └── run_detection.sh
├── shared/                         # Shared Resources
│   ├── logger.sh
│   ├── rules.conf
│   ├── logs/
│   └── tmp/
├── SERVICES.md                     # Detailed service documentation
└── README.md                       # This file
```

---

## 🚀 Quick Start

### 1. Verify System Requirements
```bash
sudo ./chabahroot/kernel-ingestion/check.sh
```

### 2. Start Complete Pipeline
```bash
sudo ./chabahroot/pipeline-orchestrator/orchestrator.sh run
```

### 3. View Alerts (in another terminal)
```bash
tail -f ./chabahroot/shared/logs/chabah.log
```

### 4. Check Status
```bash
sudo ./chabahroot/pipeline-orchestrator/orchestrator.sh status
```

---

## ⚙️ Configuration

**Centralized config**: `chabahroot/shared/rules.conf`

```bash
LOG_LEVEL="INFO"
LOG_FILE="./chabahroot/shared/logs/chabah.log"
SENSITIVE_KEYWORDS="password token secret key"
POLL_INTERVAL="2"
```

**Detection rules**: `chabahroot/rules-engine/detection_rules.json`

---

## 📊 Performance Characteristics

| Metric | Value |
|--------|-------|
| eBPF Latency | <1ms |
| CPU Overhead | 1-2% |
| Data Reduction | 10-100x |
| Ring Buffer Size | 256 KB |
| Detection Rules | 7 (extensible) |

---

## 🔧 System Requirements

- **Kernel**: Linux 4.0+ (eBPF support)
- **Config**: `CONFIG_BPF=y`, `CONFIG_BPF_SYSCALL=y`
- **Tools**: `bpftool`, `clang`, `llvm-strip`, `jq`
- **Shell**: Bash 4.0+
- **Privileges**: root (for M1 kernel operations)

---

## 📚 Documentation

- **[SERVICES.md](./chabahroot/SERVICES.md)** — Detailed service documentation
- **[GAP_ANALYSIS.md](./GAP_ANALYSIS.md)** — Implementation analysis
- **[docs/](./docs/)** — Technical references

---

## 🤝 Team & Authorship

| Service | Author |
|---------|--------|
| **M1 - Kernel Ingestion** | MOUSAAB EL HARMALI |
| **M2 - Rules Engine** | Équipe Cyber |
| **M3 - Event Normalizer** | Équipe Cyber |
| **M4 - Pipeline Orchestrator** | Équipe Cyber |

---

## ⚖️ Legal & Security

⚠️ **IMPORTANT** — This project is for **legal use only**

Unauthorized use is **illegal** and subject to legal penalties.

---

**Version**: 1.0.0 | **Updated**: 2026-05-12 | **Status**: Production Ready ✓
