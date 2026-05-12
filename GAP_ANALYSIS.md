# ChabahRoot Gap Analysis — Specification vs Implementation

**Analysis Date**: May 12, 2026  
**Specification Version**: v1.1  
**Implementation State**: Phase 1 (M1) In Progress  
**Status**: CRITICAL GAPS IDENTIFIED

---

## Executive Summary

The ChabahRoot project demonstrates foundational architecture but has **critical gaps** between specification requirements and implementation:

- ✓ **16% Complete**: Basic M1 prerequisite checking and cleanup framework
- ✗ **84% Missing**: eBPF event capture, data normalization, rules engine, integration framework
- **Blocking Issues**: No actual eBPF kernel-to-userspace communication; detection uses polling instead of real events

---

## LAYER ANALYSIS

### Layer 1: INGESTION (eBPF/tracefs) — **INCOMPLETE (20% done)**

#### Specification Requirements
```
Ingestion Layer (Couche d'ingestion):
- eBPF/tracefs connection establishment
- Probe activation on execve/fork/privilege escalation events
- Raw event retrieval with all context (PID, UID, command args)
- Ring buffer or map-based kernel↔userspace communication
- Event filtering in kernel space (<1ms latency)
```

#### Current Implementation Status

| Component | Spec Requirement | Implementation | Gap |
|-----------|------------------|-----------------|-----|
| **eBPF Compilation** | C source program targeting tracepoints | Bash functions only, no .c files | ❌ MISSING |
| **Kernel Probe Setup** | Attach to `tracepoint/syscalls/sys_enter_execve` | `attach_ebpf()` function exists but untested | ⚠️ INCOMPLETE |
| **Ring Buffer** | BPF_RINGBUF for kernel→user event stream | No BPF map structures defined | ❌ MISSING |
| **Event Struct** | Capture PID, UID, command, args, timestamp | No data structure in C | ❌ MISSING |
| **In-kernel Filter** | Filter syscalls by UID, name, rules | Only comment mentions filtering | ❌ STUBBED |
| **User-space Reader** | Poll ring buffer, parse events | No ring buffer reading code | ❌ MISSING |

#### Specific Gaps

**Gap 1.1: No eBPF C Source Program**
- **Status**: Critical
- **Current**: Embedded inline in bash (simple_filter.c)
- **Missing**: Complete eBPF program with:
  - `BPF_RINGBUF_OUTPUT()` calls to send events to userspace
  - Event capture structure (`struct event_t`) with PID, UID, comm, args
  - Privilege escalation detection logic (UID comparison)
  - Timestamp capture with `bpf_ktime_get_ns()`
- **Impact**: No actual event capture occurring
- **Owner**: M1 (Kernel Engineer)
- **Priority**: CRITICAL

**Gap 1.2: No Ring Buffer Communication**
- **Status**: Critical
- **Current**: Comments mention ring buffer in README but not implemented
- **Missing**: 
  - `struct event_t` definition in eBPF
  - `BPF_RINGBUF_OUTPUT()` macro usage
  - Userspace ring buffer reader (similar to libbpf examples)
  - Event serialization format
- **Impact**: No kernel→userspace data flow
- **Owner**: M1 + M3 (Kernel + Data Structuring)
- **Priority**: CRITICAL

**Gap 1.3: Execve Tracepoint Not Capturing Arguments**
- **Status**: High
- **Current**: Program only filters in kernel, doesn't capture cmdline
- **Missing**:
  - `ctx->args[N]` parsing from tracepoint
  - Argument buffer in ring buffer output
  - Command line extraction from `/proc/[pid]/cmdline`
- **Impact**: Cannot correlate executed commands with UID changes
- **Owner**: M1
- **Priority**: HIGH

**Gap 1.4: No Privilege Escalation Event Capture**
- **Status**: Critical
- **Current**: Only captures execve; no fork or setuid syscalls
- **Missing**:
  - `tracepoint/syscalls/sys_enter_setuid` probe
  - `tracepoint/syscalls/sys_enter_setgid` probe
  - `tracepoint/syscalls/sys_enter_execve` with UID check
  - Privilege transition context (old_uid → new_uid)
- **Impact**: Core specification requirement unfulfilled
- **Owner**: M1
- **Priority**: CRITICAL

---

### Layer 2: TRANSPORT (Buffered Sequential Reading) — **INCOMPLETE (0%)**

#### Specification Requirements
```
Transport Layer (Couche de transport):
- Continuous sequential reading from eBPF ring buffer
- Buffered queuing to decouple kernel from analysis
- Loss handling and event ordering guarantees
- Back-pressure handling when analysis is slow
```

#### Current Implementation Status

| Component | Spec Requirement | Implementation | Gap |
|-----------|------------------|-----------------|-----|
| **Ring Buffer Read Loop** | Continuous poll of ring buffer | No code exists | ❌ MISSING |
| **Buffering** | Decouple kernel from analysis | Events go direct to logging | ❌ MISSING |
| **Loss Handling** | Track lost events, alert | No loss tracking | ❌ MISSING |
| **Ordering** | Maintain timestamp order | ps-based, unordered | ❌ MISSING |
| **Back-pressure** | Handle slow analysis | No queuing mechanism | ❌ MISSING |

#### Specific Gaps

**Gap 2.1: No Ring Buffer Reader Loop**
- **Status**: Critical
- **Current**: `defensive.sh` uses `ps -eo uid,pid,...` polling (every 2-5 seconds)
- **Missing**:
  - Ring buffer polling code (using libbpf or raw BPF map reads)
  - Event callback handler
  - Timestamp-based ordering
- **Impact**: Detection is 2-5 second delayed; missing events if kernel buffer overflows
- **Owner**: M3 (Collection Engineer)
- **Priority**: CRITICAL

**Gap 2.2: No Event Buffering Queue**
- **Status**: High
- **Current**: Events logged immediately to disk or stdout
- **Missing**:
  - In-memory circular buffer for events
  - Dequeue-process-ack pattern
  - Backpressure when disk I/O slow
- **Impact**: Kernel ring buffer can overflow; events lost silently
- **Owner**: M3
- **Priority**: HIGH

**Gap 2.3: No Loss Detection/Reporting**
- **Status**: Medium
- **Current**: No mechanism to detect dropped events
- **Missing**:
  - Sequence number tracking in ring buffer
  - Loss counter in eBPF map
  - Alert on loss threshold (e.g., >100 events/sec dropped)
- **Impact**: Silent data loss; no audit trail completeness guarantee
- **Owner**: M3 + M4 (Collection + Integration)
- **Priority**: MEDIUM

---

### Layer 3: ANALYSIS (Filtering, Classification, Enrichment) — **INCOMPLETE (30%)**

#### Specification Requirements
```
Analysis Layer (Couche d'analyse):
1. Module de surveillance des exécutions: Program execution monitoring
   - Binary name/path logging
   - Arguments capture
   - PID/UID/timestamp association
   
2. Module de détection des changements de privilèges: Privilege escalation detection
   - UID transition detection (real_uid → effective_uid)
   - Alert generation on escalation events
   
3. Module d'audit contextuel: Contextual auditing
   - Horodatage (timestamps)
   - Metadata storage (PID, UID, process type)
   - Centralized journal preparation
```

#### Current Implementation Status

| Component | Spec Requirement | Implementation | Gap |
|-----------|------------------|-----------------|-----|
| **Rule Engine** | Pluggable rules system | Hardcoded functions | ⚠️ PARTIAL |
| **Exec Monitoring** | Capture binary/args/context | Reads `/proc` via ps | ⚠️ PARTIAL |
| **Privilege Detection** | Real-time UID transition detection | Polls `ps` for UID=0 | ❌ INSUFFICIENT |
| **Context Enrichment** | Timestamps, metadata, parent tracking | Basic logging only | ⚠️ PARTIAL |
| **Alert Rules** | Configurable thresholds | Hardcoded in code | ❌ MISSING |

#### Specific Gaps

**Gap 3.1: No Formal Detection Rules Engine (M2 Requirement)**
- **Status**: Critical
- **Current**: Hardcoded rules in `defensive.sh`:
  ```bash
  check_suspicious_process() {
      local suspicious="nc ncat netcat bash sh perl python ruby"
      for suspect in $suspicious; do
          [[ "$cmd" == "$suspect"* ]] && log_alert ...
  }
  ```
- **Missing**:
  - Rule definition format (JSON/YAML/DSL)
  - Rule loading mechanism
  - Context-aware rule evaluation (not just process name)
  - Rule composition (AND/OR/NOT logic)
  - Performance metrics per rule
  - Example rule file:
    ```yaml
    rule:
      name: "Privilege Escalation via Bash"
      condition: "uid == 0 AND (cmd == 'bash' OR cmd == 'sh') AND ppid_uid != 0"
      severity: HIGH
      action: ALERT
    ```
- **Impact**: Cannot customize detection without code changes
- **Owner**: M2 (Detection Engineer)
- **Priority**: CRITICAL

**Gap 3.2: Reactive vs Event-Driven Detection**
- **Status**: Critical
- **Current**: `defensive.sh` polls every 2-5 seconds:
  ```bash
  while IFS= read -r uid pid ppid cmd; do
      [[ "$uid" -eq "$TARGET_UID" ]] || continue
      # React to what's already running
  ```
- **Missing**:
  - Event-driven detection from eBPF ring buffer
  - Real-time capture of privilege transition (at the moment it happens)
  - Parent process context (who ran the escalated command?)
- **Impact**: Misses short-lived processes; 2-5s detection lag
- **Owner**: M1 + M2
- **Priority**: CRITICAL

**Gap 3.3: No Privilege Transition Capture**
- **Status**: Critical
- **Current**: Only detects running processes with UID=0, not transitions
- **Missing**:
  - Capture old_uid and new_uid separately
  - Detect methods (sudo, setuid binary, fork from root, etc.)
  - Timestamp of transition
  - User who triggered it (from audit log)
- **Example missing**: Scenario: `user` runs `sudo bash` → should capture:
  ```
  Event: PrivilegeTransition
  timestamp: 2026-05-12T14:23:45.123Z
  user: user (UID 1000)
  process: bash (PID 12345)
  uid_transition: 1000 → 0
  method: sudo
  parent_cmd: /usr/bin/sudo
  ```
- **Owner**: M1 + M2
- **Priority**: CRITICAL

**Gap 3.4: No Parent Process Tracking**
- **Status**: High
- **Current**: Tracks PID, PPID from ps output but doesn't link context
- **Missing**:
  - Parent command name retrieval
  - Full process ancestry (grandparent, etc.)
  - Context enrichment (terminal, session, controlling tty)
  - Example missing data:
    ```
    bash (PID 12345) 
    └─ parent: sudo (PPID 12344)
       └─ parent: gnome-terminal (PPID 1000)
    ```
- **Owner**: M3 (Data Structuring)
- **Priority**: HIGH

**Gap 3.5: Incomplete Offensive Audit Module**
- **Status**: Medium
- **Current**: `offensive.sh` has basic SUID/sudoers scanning
- **Missing**:
  - File permissions analysis (world-writable libs, setgid files)
  - Capability analysis (`getcap /usr/bin/ping` etc)
  - SELinux context violations
  - AppArmor/seccomp bypass vectors
  - Scheduled task analysis (cron, at, timers)
  - Kernel module check for rootkits
- **Owner**: M2
- **Priority**: MEDIUM

---

### Layer 4: OUTPUT (Structured Logs, Alerts, Reports) — **INCOMPLETE (40%)**

#### Specification Requirements
```
Output Layer (Couche de sortie):
- Structured alerts with severity levels
- Reports with aggregation
- Journal entries (syslog/systemd compatible)
- Multiple output formats (JSON, CSV, syslog, markdown)
- Sensitive data filtering
```

#### Current Implementation Status

| Component | Spec Requirement | Implementation | Gap |
|-----------|------------------|-----------------|-----|
| **Structured Logging** | JSON/CSV/structured format | File + ANSI colored text | ⚠️ PARTIAL |
| **Alert Levels** | Severity levels (INFO/WARN/ALERT) | 4 levels defined | ✓ BASIC |
| **Sensitive Filtering** | Redact passwords/tokens | Basic keyword matching | ⚠️ PARTIAL |
| **Systemd Journal** | Journalctl integration | Only reads journalctl, doesn't write | ❌ INCOMPLETE |
| **Report Generation** | Aggregated summaries | No reporting module | ❌ MISSING |
| **Multiple Formats** | JSON, CSV, syslog, markdown | Text file only | ❌ MISSING |

#### Specific Gaps

**Gap 4.1: No JSON/Structured Output**
- **Status**: High
- **Current**: Text file with ANSI colors:
  ```
  [2026-05-12 14:23:45] [ALERT] [DEFENSIVE] ROOT escalation: PID=12345 PPID=1234 CMD=bash
  ```
- **Missing**:
  - JSON format for parsing/analysis:
    ```json
    {
      "timestamp": "2026-05-12T14:23:45.123Z",
      "level": "ALERT",
      "module": "DEFENSIVE",
      "event_type": "privilege_escalation",
      "pid": 12345,
      "ppid": 1234,
      "uid_new": 0,
      "uid_old": 1000,
      "command": "bash"
    }
    ```
  - Schema validation
- **Impact**: Cannot integrate with SIEM/ELK/Splunk
- **Owner**: M3 + M4
- **Priority**: HIGH

**Gap 4.2: No Systemd Journal Integration (Write)**
- **Status**: High
- **Current**: Only reads journalctl; logger.sh writes to local file
- **Missing**:
  - Integration with `systemd-cat` or `sd_journal_send()`
  - Bash implementation:
    ```bash
    log_to_journal() {
        echo "$@" | systemd-cat -t ChabahRoot -p alert
    }
    ```
  - Priority level mapping
- **Impact**: Logs not available via `journalctl -u chabahroot`
- **Owner**: M3
- **Priority**: HIGH

**Gap 4.3: No Report Generation**
- **Status**: Medium
- **Current**: No aggregation or reporting
- **Missing**:
  - Daily/hourly summary reports
  - Per-user escalation counts
  - Process frequency analysis
  - Trend detection
  - Example report structure:
    ```
    ChabahRoot Security Report — 2026-05-12
    ==========================================
    Total Events: 42
    Privilege Escalations: 12
    Suspicious Processes: 3
    By User:
      user1: 8 escalations
      user2: 4 escalations
    Top Escalated Commands:
      bash: 6
      sudo: 3
      su: 2
    ```
- **Owner**: M4
- **Priority**: MEDIUM

**Gap 4.4: Sensitive Data Filtering Too Simple**
- **Status**: Medium
- **Current**: Keyword-based filtering in rules.conf:
  ```bash
  SENSITIVE_KEYWORDS="pass password token secret key"
  ```
- **Missing**:
  - Regex-based patterns for credit cards, SSNs, API keys
  - Context-aware redaction (not just keywords)
  - Customizable filter rules
  - Audit trail of filtered events
- **Owner**: M3
- **Priority**: MEDIUM

---

## FUNCTIONAL MODULES ANALYSIS

### Module 1: Execution Monitoring (Surveillance des exécutions) — **30% Complete**

| Requirement | Status | Notes |
|------------|--------|-------|
| Binary name/path | ⚠️ PARTIAL | From ps output, not real-time events |
| Arguments capture | ❌ MISSING | ps shows only first 80 chars of COMM |
| Full cmdline | ❌ MISSING | Need `/proc/[pid]/cmdline` parsing |
| PID/UID/timestamp | ✓ PARTIAL | Available from ps, but polling-based |
| Event ordering | ❌ MISSING | No temporal ordering guarantee |

**Gap**: Missing real-time event capture from eBPF ring buffer

---

### Module 2: Privilege Escalation Detection (Détection des changements de privilèges) — **10% Complete**

| Requirement | Status | Notes |
|------------|--------|-------|
| UID transition detection | ❌ MISSING | No setuid/setgid probes |
| Real-time capture | ❌ MISSING | Only polls running processes |
| Alert generation | ✓ BASIC | Alerts work but lack context |
| Escalation context | ❌ MISSING | No method detection (sudo/setuid/fork) |
| Threshold-based | ❌ MISSING | No rate limiting or thresholds |

**Gap**: Core specification requirement fundamentally unimplemented

---

### Module 3: Contextual Audit (Audit contextuel) — **40% Complete**

| Requirement | Status | Notes |
|------------|--------|-------|
| Timestamps | ✓ PARTIAL | Logged but in local time, not UTC |
| PID tracking | ✓ BASIC | Basic tracking exists |
| UID tracking | ✓ BASIC | Basic tracking exists |
| Parent process context | ❌ MISSING | No ppid command name |
| Centralized journal | ⚠️ PARTIAL | Only reads, doesn't write to journald |
| Metadata storage | ⚠️ MINIMAL | Text file, no structure |

**Gap**: No integration with systemd journal; insufficient parent context

---

## TEAM RESPONSIBILITY MATRIX

### M1 — Kernel Integration Engineer

**Should Own:**
- eBPF program source files (.c)
- Kernel probe attachment logic
- Ring buffer setup and cleanup
- Performance tuning (CPU%, memory)

**Current Status:** ❌ CRITICAL GAPS
- Skeleton code exists but no actual eBPF sources
- No ring buffer implementation
- `ebpf_integration.sh` is stub; only basic compilation/loading

**Missing Deliverables:**
1. Complete eBPF program with event capture
2. Ring buffer output writer
3. Privilege escalation probe attachment
4. Error handling and validation

---

### M2 — Detection Rules Engineer

**Should Own:**
- Formal rules system (not hardcoded)
- Detection logic and algorithms
- Alert thresholds and configurations
- Security analysis (SUID audit, sudoers, etc.)

**Current Status:** ❌ CRITICAL GAPS
- Hardcoded rules in bash functions
- No pluggable rule system
- Weak SUID/sudoers analysis
- No privilege transition detection

**Missing Deliverables:**
1. Rules engine and format specification
2. Privilege transition detection logic
3. Complete audit checks
4. Rule examples and templates

---

### M3 — Data Collection/Normalization Engineer

**Should Own:**
- Event parsing and extraction
- Data structure definitions
- Field mapping and enrichment
- Output format generation

**Current Status:** ❌ CRITICAL GAPS
- No separation of logging from data normalization
- No structured output formats
- No field extraction/parsing layer
- Missing parent process enrichment

**Missing Deliverables:**
1. Event data structure schema
2. Ring buffer reader implementation
3. JSON/CSV output formatters
4. Parent process context enrichment

---

### M4 — Integration/Testing Engineer

**Should Own:**
- End-to-end pipeline assembly
- Integration testing
- Resource usage monitoring
- Health checks and recovery

**Current Status:** ❌ MISSING
- No testing framework exists
- No pipeline validation
- No health monitoring
- No recovery mechanisms

**Missing Deliverables:**
1. End-to-end test suite
2. Integration validation tests
3. Resource usage monitoring
4. Error recovery mechanisms

---

## IMPLEMENTATION PRIORITY MATRIX

```
PRIORITY | OWNER  | COMPONENT                           | EFFORT | IMPACT
---------|--------|-------------------------------------|--------|--------
CRITICAL | M1     | eBPF program with ring buffer      | 3 days | BLOCKING
CRITICAL | M1     | Privilege escalation probes        | 2 days | BLOCKING  
CRITICAL | M2     | Detection rules engine             | 3 days | BLOCKING
CRITICAL | M3     | Ring buffer reader loop            | 2 days | BLOCKING
CRITICAL | M3     | Event structure normalization      | 2 days | BLOCKING
         |        |                                     |        |
HIGH     | M3     | JSON output formatter              | 1 day  | SIEM
HIGH     | M2     | Complete SUID/sudoers audit        | 2 days | SECURITY
HIGH     | M3     | Systemd journal integration        | 1 day  | LOGGING
HIGH     | M3     | Parent process enrichment          | 1 day  | CONTEXT
         |        |                                     |        |
MEDIUM   | M3     | Sensitive data filtering (regex)   | 1 day  | PRIVACY
MEDIUM   | M4     | End-to-end testing framework       | 2 days | QUALITY
MEDIUM   | M3     | Event loss detection               | 1 day  | RELIABILITY
MEDIUM   | M4     | Resource usage monitoring          | 1 day  | OPS

TOTAL CRITICAL EFFORT: ~10 days (M1+M2+M3 combined)
```

---

## PRODUCTION QUALITY GAPS

### Error Handling — ❌ DEFICIENT

| Scenario | Current | Missing |
|----------|---------|---------|
| eBPF load fails | Silent return 1 | Logs to journal, alerts ops |
| Ring buffer overflow | Silent loss | Detects, counts, alerts |
| Permission denied on /proc | Skips | Retries with elevated privileges |
| Disk full on logging | Fails | Falls back to syslog |
| Process disappears mid-scan | Skips | Log error with PID |

### Input Validation — ❌ MISSING

| Input | Validation | Impact |
|-------|-----------|--------|
| POLL_INTERVAL from config | None | Could cause DoS if 0 or negative |
| TARGET_UID from config | None | Accepts invalid values |
| SENSITIVE_KEYWORDS | None | No escaping for regex |
| Command arguments from ps | None | Could cause injection in alerts |

### Idempotency — ⚠️ PARTIAL

| Operation | Idempotent? | Notes |
|-----------|-----------|-------|
| init.sh | ✓ Yes | Multiple runs OK |
| cleanup.sh | ✓ Yes | Handles missing resources |
| ebpf_integration.sh | ❌ No | Program IDs not tracked |
| defensive.sh PID file | ❌ No | Could have orphaned tracking |

### Race Conditions — ⚠️ POTENTIAL

- Concurrent writes to `/tmp/seen_pids.tmp`
- Ring buffer reader vs writer (no sync)
- Multiple instances of run.sh competing for log file

---

## DATA FLOW GAPS

### Current (Broken) Flow
```
┌─────────────────────────────────────────────────┐
│ detection.sh (journalctl reader)               │
│  → Watches journalctl for sudo transitions     │
│  → Logs to file with notify-send               │
└─────────────────────────────────────────────────┘

         ↓ (DISCONNECTED)

┌─────────────────────────────────────────────────┐
│ run.sh (detection orchestrator)                │
│  → Starts defensive.sh in background           │
│  → Defensive: polls ps every 2s                │
│  → Logs to logger.sh                           │
└─────────────────────────────────────────────────┘

         ↓ (NO CONNECTION)

┌─────────────────────────────────────────────────┐
│ M1 Layer (ebpf_integration.sh)                 │
│  → Checks tools, loads eBPF programs           │
│  → But: NO ACTUAL EVENT CAPTURE                │
│  → Ring buffer never created/read              │
└─────────────────────────────────────────────────┘
```

### Specification Flow (To Be Implemented)
```
┌──────────────────────────────┐
│ Linux Kernel Events          │
│ - execve(), setuid(), fork() │
└──────────────────┬───────────┘
                   │
        ┌──────────▼──────────┐
        │ M1: eBPF Filter     │
        │ In-kernel filtering │
        │ Ring buffer output  │
        └──────────┬──────────┘
                   │
        ┌──────────▼──────────────┐
        │ M3: Ring Buffer Reader  │
        │ Event normalization     │
        │ Field extraction        │
        └──────────┬──────────────┘
                   │
        ┌──────────▼──────────────┐
        │ M2: Detection Rules     │
        │ Alert generation       │
        │ Context enrichment      │
        └──────────┬──────────────┘
                   │
        ┌──────────▼──────────────┐
        │ M4: Output Layer       │
        │ Structured logs        │
        │ Systemd journal        │
        └────────────────────────┘
```

---

## FRENCH LANGUAGE COMMENTS — ✓ GOOD

Files using French properly:
- ✓ `chabahroot/m1/init.sh` — All comments in French
- ✓ `chabahroot/m1/check.sh` — All comments in French
- ✓ `chabahroot/m1/ebpf_integration.sh` — All comments in French
- ✓ `chabahroot/m1/cleanup.sh` — French in function names/comments
- ✓ `chabahroot/m1/lib/lib_utils.sh` — French function comments
- ✓ `detection/defensive.sh` — French comments
- ✓ `detection/offensive.sh` — French comments
- ⚠️ `detection/logger.sh` — Mixed (French vars, English comments)
- ⚠️ `detection/run.sh` — English comments (should be French)
- ✗ `detection.sh` — All English comments
- ✓ README.md — French with technical English terms

**Recommendation**: Standardize language policy (all French for French-locale systems)

---

## SUMMARY TABLE: Specification Compliance

| Layer | Module | Completion | Status | Blocking? |
|-------|--------|------------|--------|-----------|
| Ingestion | eBPF Kernel | 20% | CRITICAL GAP | YES |
| Transport | Ring Buffer | 0% | MISSING | YES |
| Analysis | Rules Engine | 10% | CRITICAL GAP | YES |
| Analysis | Exec Monitor | 30% | INCOMPLETE | YES |
| Analysis | Priv Detection | 10% | CRITICAL GAP | YES |
| Analysis | Audit Context | 40% | INCOMPLETE | NO |
| Output | Structured Logs | 40% | INCOMPLETE | NO |
| M1 | Kernel Engineer Tasks | 30% | CRITICAL GAPS | YES |
| M2 | Rules Engineer Tasks | 10% | CRITICAL GAPS | YES |
| M3 | Data Engineer Tasks | 20% | CRITICAL GAPS | YES |
| M4 | Integration Tasks | 0% | MISSING | YES |

**Overall Completion**: **~18%**  
**Blocking Issues**: 5 critical  
**Unblocks Phases 2-5**: NO

---

## RECOMMENDED IMPLEMENTATION ORDER

### Phase 1a — Unblock M1 (Week 1)
1. **Create complete eBPF program** (simple_filter.c → event_capture.c)
   - Define `struct event_t` with PID, UID, command, timestamp
   - Implement `tracepoint/syscalls/sys_enter_execve` probe
   - Add `tracepoint/syscalls/sys_enter_setuid` probe
   - Create ring buffer output: `BPF_RINGBUF_OUTPUT(events, 10)`

2. **Implement ring buffer reader** (M3 responsibility)
   - Shell script using libbpf or raw BPF map reads
   - Parse events from ring buffer
   - Output to stdout for debugging

3. **Update ebpf_integration.sh**
   - Compile new event_capture.c
   - Load ring buffer probe
   - Start background reader process

### Phase 1b — Implement M2 Rules Engine (Week 2)
1. **Pluggable rules format** (JSON or simple DSL)
2. **Detection logic** for privilege transitions
3. **Alert generation** with context

### Phase 1c — Complete M3 Data Normalization (Week 2)
1. Ring buffer reader in proper module
2. JSON output formatter
3. Parent process enrichment
4. Systemd journal integration

### Phase 1d — M4 Integration/Testing (Week 3)
1. End-to-end test suite
2. Error recovery
3. Documentation

---

## NEXT STEPS FOR EACH TEAM MEMBER

### M1: Kernel Integration Engineer
**Immediate Actions:**
1. [ ] Create `chabahroot/m1/event_capture.c` with complete eBPF program
2. [ ] Define event structure with all required fields
3. [ ] Implement ring buffer output in eBPF
4. [ ] Test compilation and loading
5. [ ] Update `ebpf_integration.sh` to use new program

**Deliverable**: Working eBPF event capture with ring buffer output to userspace

---

### M2: Detection Rules Engineer  
**Immediate Actions:**
1. [ ] Design rules format (JSON/YAML)
2. [ ] Create rules engine in bash/awk
3. [ ] Implement privilege transition detection logic
4. [ ] Create comprehensive SUID/sudoers audit
5. [ ] Define rule examples

**Deliverable**: Pluggable rules system with privilege escalation detection

---

### M3: Data Collection Engineer
**Immediate Actions:**
1. [ ] Implement ring buffer reader
2. [ ] Define normalized event schema
3. [ ] Create JSON output formatter
4. [ ] Add parent process enrichment
5. [ ] Integrate with systemd journal

**Deliverable**: Event normalization and structured output

---

### M4: Integration Engineer
**Immediate Actions:**
1. [ ] Design end-to-end test suite
2. [ ] Create pipeline validation tests
3. [ ] Implement health checks
4. [ ] Error recovery mechanisms
5. [ ] Integration documentation

**Deliverable**: Complete testing framework and integration validation

---

## Appendix: Critical Code Stubs Needed

### Stub 1: eBPF Program (event_capture.c)
```c
// MISSING: Complete event capture with ring buffer
#include <linux/bpf.h>
#include <bpf/bpf_helpers.h>

struct event_t {
    u32 pid;
    u32 uid;
    u32 old_uid;
    char comm[16];
    char cmdline[256];
    u64 ts;
};

struct {
    __uint(type, BPF_MAP_TYPE_RINGBUF);
    __uint(max_entries, 256 * 1024);
} events SEC(".maps");

SEC("tracepoint/syscalls/sys_enter_execve")
int trace_execve(struct trace_event_raw_sys_enter *ctx) {
    // TODO: Extract event data, output to ring buffer
}
```

### Stub 2: Ring Buffer Reader (M3 responsibility)
```bash
# MISSING: Implement in detection layer
read_ring_buffer() {
    # TODO: Loop reading from /sys/kernel/debug/tracing/trace_pipe
    # or use libbpf if available
}
```

### Stub 3: Rules Engine (M2 responsibility)
```bash
# MISSING: Pluggable rules system
evaluate_rules() {
    local event="$1"  # JSON event from M3
    # TODO: Load rules from config, apply detection logic
}
```

---

**Document Created**: 2026-05-12  
**Gap Analysis Status**: COMPLETE  
**Approval Required**: Architecture Review  
**Next Review**: After Phase 1a completion
